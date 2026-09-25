# Physio carrier PCB

This is Majock's two-layer Altium carrier board for the next Physio prototype. It replaces breadboard interconnections with traces and socket headers to reduce wiring and make the arm-mounted assembly more compact. PCBWay sponsored fabrication and assembly.

**Status:** factory photos received; boards not yet delivered or tested by Majock. These files document the design and local manufacturing exports. They are not a tested build release.

## Design files

Open [physio.PrjPcb](altium/physio.PrjPcb) in Altium Designer. Its source documents and local libraries are included together:

| File | Purpose |
| --- | --- |
| [Sheet2.SchDoc](altium/Sheet2.SchDoc) | Schematic and header connections |
| [physio.PcbDoc](altium/physio.PcbDoc) | Board layout |
| [Physio_Symbols.SchLib](altium/Physio_Symbols.SchLib) | Schematic symbols |
| [Physio_Footprints.PcbLib](altium/Physio_Footprints.PcbLib) | PCB footprints |

The source files were copied without modification. Altium's generated-document entries may point to the original output folder; the curated exports in this repository are under `manufacturing/`.

## Manufacturing exports

| File | Contents |
| --- | --- |
| [physio_gerbers.zip](manufacturing/physio_gerbers.zip) | Top/bottom copper, solder mask, silkscreen and paste layers; mechanical outputs and NC drill file |
| [physio_BOM.xlsx](manufacturing/physio_BOM.xlsx) | Original local BOM export |
| [physio_pick_place.csv](manufacturing/physio_pick_place.csv) | Original placement export, including its units and revision header |

The Gerber archive packages the existing local exports without regenerating them. The BOM and placement file are copied unchanged. This documents the files available locally; it does not establish that they match every later factory-side adjustment.

The schematic and placement export describe five header components: three 1×8, one 1×5, and one 1×2, at 2.54 mm pitch. The factory photos show socket headers fitted to the carrier. The ESP32 and IMU modules are separate from this assembly, and the carrier has no onboard charger.

## Before bringing up the board

Compare the schematic, PCB layout, and the pinout of each actual module before fitting it. In particular, the source schematic uses a `5V5` power-net label while the factory silkscreen shows `5V`; that label difference is not a verified supply-voltage specification.

The firmware also needs its sensor roles checked against the physical wiring: `main.cpp` currently constructs the bicep sensor at `0x69` and wrist sensor at `0x68`, while its startup messages say the reverse. The README therefore does not prescribe sensor placement from those messages.

Once the boards arrive, the first checks are module fit, power-rail continuity, sensor discovery on I²C, and streaming both sensors to the iOS app. None of those checks has been completed on the custom board yet.

[Back to the project README](../README.md)
