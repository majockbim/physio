import Foundation
import Accelerate
@preconcurrency import ZeticMLange

// Swift port of inference.py + data_loader.py preprocessing pipeline.
// Preprocessing exactly matches Python training:
//   1. Extract 12 IMU channels in model-expected order
//   2. Global per-channel Z-score normalization (Unified_stats.npz)
//   3. Linear interpolation to 128 timesteps (align_corners=False)
//   4. ZeticMLange inference → softmax → 0-100 score

enum MovementQualityInference {

    // MARK: - Constants

    static let interpolationSize = 128
    private static let channelCount = 12

    // Global per-channel normalization stats from Unified_stats.npz.
    // Channel order: [wrist_acc_x/y/z, wrist_gyro_x/y/z, bicep_acc_x/y/z, bicep_gyro_x/y/z]
    private static let globalMean: [Float] = [
         2.3763542,   0.25314444,  4.5050979,
        -0.0054391,   0.00092947, -0.0021757,
         1.3750609,   6.6231956,   4.0471716,
         0.0012042,   0.0034773,  -0.0011472
    ]
    private static let globalStd: [Float] = [
        5.7343864,  5.555813,   5.2093425,
        0.6993381,  1.0473762,  0.810547,
        4.517454,   3.0211089,  3.5388074,
        0.42847854, 0.48747784, 0.5245762
    ]

    // MARK: - Public API

    /// Full pipeline: extract → normalize → interpolate → inference → 0-100 score.
    static func getLiveScore(from payloads: [SensorPayload], using model: ZeticMLangeModel) throws -> Int {
        guard payloads.count >= 2 else { return 0 }
        let (features, T) = extractChannels(from: payloads)
        let normalized    = normalizeFeatures(features, timesteps: T)
        let resampled     = interpolateToFixedLength(normalized, timesteps: T)
        return try runInference(on: resampled, using: model)
    }

    // MARK: - Step 1: Extract channels

    // Row-major (T × 12) buffer. Channel order matches data_loader.py:
    // wrist first (cols 0-5), bicep second (cols 6-11).
    private static func extractChannels(from payloads: [SensorPayload]) -> ([Float], Int) {
        var out = [Float]()
        out.reserveCapacity(payloads.count * channelCount)
        for p in payloads {
            out.append(p.wrist_accel_x); out.append(p.wrist_accel_y); out.append(p.wrist_accel_z)
            out.append(p.wrist_gyro_x);  out.append(p.wrist_gyro_y);  out.append(p.wrist_gyro_z)
            out.append(p.bicep_accel_x); out.append(p.bicep_accel_y); out.append(p.bicep_accel_z)
            out.append(p.bicep_gyro_x);  out.append(p.bicep_gyro_y);  out.append(p.bicep_gyro_z)
        }
        return (out, payloads.count)
    }

    // MARK: - Step 2: Normalize

    // x̂ = (x − μ) / (σ + ε) per channel.
    // vDSP_vsmsa with stride `channelCount` processes each interleaved column in one SIMD call.
    private static func normalizeFeatures(_ data: [Float], timesteps T: Int) -> [Float] {
        var output = [Float](repeating: 0, count: data.count)
        data.withUnsafeBufferPointer { src in
            output.withUnsafeMutableBufferPointer { dst in
                let s = src.baseAddress!
                let d = dst.baseAddress!
                for c in 0..<channelCount {
                    var scale  = 1.0 / (globalStd[c] + 1e-7)
                    var offset = -globalMean[c] * scale
                    vDSP_vsmsa(s + c, channelCount, &scale, &offset,
                               d + c, channelCount, vDSP_Length(T))
                }
            }
        }
        return output
    }

    // MARK: - Step 3: Interpolate

    // (T × 12) → (128 × 12), matching F.interpolate(mode='linear', align_corners=False).
    // src_x = (i + 0.5) * T/128 − 0.5, clamped to [0, T−1.0001].
    // vDSP_vlint: C[n] = A[⌊B[n]⌋] + frac(B[n]) × (A[⌊B[n]⌋+1] − A[⌊B[n]⌋])
    private static func interpolateToFixedLength(_ data: [Float], timesteps T: Int) -> [Float] {
        let outSize = interpolationSize
        var output  = [Float](repeating: 0, count: outSize * channelCount)

        let maxIdx = Float(T) - 1.0001
        let indices: [Float] = (0..<outSize).map { i in
            max(0, min((Float(i) + 0.5) * Float(T) / Float(outSize) - 0.5, maxIdx))
        }

        var channelBuf = [Float](repeating: 0, count: T)
        var outBuf     = [Float](repeating: 0, count: outSize)

        for c in 0..<channelCount {
            for t in 0..<T { channelBuf[t] = data[t * channelCount + c] }

            indices.withUnsafeBufferPointer { idxPtr in
                channelBuf.withUnsafeBufferPointer { srcPtr in
                    outBuf.withUnsafeMutableBufferPointer { dstPtr in
                        vDSP_vlint(srcPtr.baseAddress!, idxPtr.baseAddress!, 1,
                                   dstPtr.baseAddress!, 1,
                                   vDSP_Length(outSize), vDSP_Length(T))
                    }
                }
            }

            for t in 0..<outSize { output[t * channelCount + c] = outBuf[t] }
        }
        return output
    }

    // MARK: - Step 4: Inference

    // Packs (128 × 12) float buffer into a Tensor, runs the model,
    // applies numerically-stable softmax, returns int(P(healthy) × 100).
    private static func runInference(on data: [Float], using model: ZeticMLangeModel) throws -> Int {
        let inputData = data.withUnsafeBufferPointer { Data(buffer: $0) }
        let tensor    = Tensor(data: inputData,
                               dataType: BuiltinDataType.float32,
                               shape: [1, interpolationSize, channelCount])

        let outputs = try model.run(inputs: [tensor])
        let logits  = DataUtils.dataToFloatArray(outputs[0].data)
        guard logits.count >= 2 else { return 0 }

        // logits[0] = stroke, logits[1] = healthy
        let l0 = logits[0], l1 = logits[1]
        let shift = max(l0, l1)
        let e0 = exp(l0 - shift), e1 = exp(l1 - shift)
        let healthyProb = e1 / (e0 + e1)

        return Int(healthyProb * 100)
    }
}
