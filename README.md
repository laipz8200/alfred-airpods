# AirPods for Alfred

An offline Alfred workflow for AirPods battery levels, listening modes, and making AirPods your Mac's default sound output.

## Install

1. Install **Alfred 5 with the Powerpack** on **macOS 13 or newer**.
2. Pair your AirPods with this Mac in Bluetooth settings.
3. [Download AirPods.alfredworkflow](https://github.com/laipz8200/alfred-airpods/releases/latest/download/AirPods.alfredworkflow), then open it to import into Alfred.
4. In **Configure Workflow…**, keep the keyword `airpods` or enter your preferred prefix. The optional **Preferred AirPods** field accepts an exact Bluetooth device name or Bluetooth address. Leave it empty for automatic AirPods detection.

The packaged workflow contains a native executable for Apple silicon and Intel Macs. It needs no Homebrew packages, Python runtime, or compiler. macOS may ask for Bluetooth permission; allow Alfred to access Bluetooth.

The executable targets macOS 13 and newer; it has not been tested on macOS 13.

## Use

Open Alfred and enter:

| Command | Result |
| --- | --- |
| `airpods` | Show available controls and battery information. |
| `airpods battery` | Show available earbud and case battery levels. Select the result to display a notification. |
| `airpods connect` | Connect the selected AirPods and make them the default audio output. |
| `airpods mode` | Show supported listening modes. |
| `airpods mode off` | Turn noise control off, when permitted by the device. |
| `airpods mode anc` | Turn on noise cancellation. |
| `airpods mode transparency` | Turn on Transparency mode. |
| `airpods mode adaptive` | Turn on Adaptive mode, when supported. |

Replace `airpods` in these examples when you change the keyword prefix. Type to narrow results and press Return to act.

## Device behavior

- AirPods must already be paired. Take the earbuds out of their case or open the case so macOS can reach them.
- Automatic discovery looks for **AirPods** in paired device names and prefers the current audio output. If you renamed your AirPods without that word, enter their exact name in **Preferred AirPods**.
- Battery details are whatever macOS currently exposes. Individual earbuds and the case may be unavailable or reflect the last reported value; a closed, sleeping case usually does not provide a live reading.
- Listening controls depend on the connected AirPods model and macOS version. Unsupported controls stay unavailable. On some models, **Off** must first be allowed in the AirPods settings.
- Listening mode control uses macOS's undocumented CoreAudio properties, whose selectors are documented in the [pods-control implementation](https://github.com/raulgg/pods-control/blob/main/Sources/AirPodsControl/CoreAudioRoutingBackend.swift). The workflow checks the reported capabilities and reads the mode back after changing it. This confirms macOS's reported state, not a separate acknowledgement from the accessory. A future macOS update could change this interface.
- **Connect** changes the default sound output only. It does not change the microphone or enable a background service. macOS and other Apple devices may subsequently change the audio route through automatic switching.

## Troubleshooting

If no AirPods appear, check pairing and Bluetooth permission, and try an exact device name in **Preferred AirPods**. With several paired AirPods, setting this field avoids selecting the wrong pair.

If battery values are missing, connect the AirPods and open the case, then run the command again. Missing information is shown as unavailable rather than zero.

If a mode is unavailable or cannot be changed, verify that the AirPods are connected and support it. For **Off**, check the AirPods settings for **Allow Off Listening Mode**. Use Alfred's workflow debugger to inspect other errors.

## Build from source

Install Apple's Xcode Command Line Tools and Python 3, then run:

```sh
git clone https://github.com/laipz8200/alfred-airpods.git
cd alfred-airpods
python3 scripts/build.py
```

The build compiles both Mac architectures, creates an ad hoc signed universal executable, runs the helper's read-only self-tests and invalid-mode checks, validates the workflow wiring, and creates `dist/AirPods.alfredworkflow` and `dist/AirPods-source.zip`. Run `python3 scripts/build.py --check` to validate the workflow metadata without compiling or accessing AirPods.

The workflow sends no network requests and stores no account credentials. It has no hotkeys or background daemon.

## Validation

Validated on macOS 27.0.1 with connected AirPods Pro: battery readings, native command results, selecting the already-active default output, switching to Transparency, and restoring the initial Noise Cancellation mode. Mode checks confirm macOS's reported state. Parser/error/capability self-tests and workflow wiring checks also pass.

Intel is compiled but not runtime-tested. macOS 13–26, reconnecting disconnected hardware, and live Off/Adaptive changes have not been tested. The helper targets macOS 13; listening controls are enabled only when macOS exposes the required properties.

## References

- [Alfred workflow configuration](https://www.alfredapp.com/help/workflows/workflow-configuration/)
- [Alfred configurable keywords](https://www.alfredapp.com/help/workflows/advanced/keywords/)
- [Alfred script arguments](https://www.alfredapp.com/help/workflows/actions/run-script/)

## License

MIT. See [LICENSE](LICENSE).

The workflow icon is an AI-generated illustration of AirPods Pro.

AirPods is a trademark of Apple Inc. This independent project is not affiliated with Apple or Alfred.
