# RF4 camera initializer for Apple Silicon Macs

`rf4` initializes the **RF4 RF-4KC7** microscope camera so macOS on Apple Silicon can receive video after a cold start.

It completes the UVC negotiation and exits. Use a capture application to view or record video through the standard macOS UVC driver.

## The problem

After a cold start, macOS detected the camera and its USB controls responded. Video capture received **no data**. The same camera worked with the standard Windows camera driver. Initializing it on Windows, then moving its USB connection to the Mac while keeping camera power connected, also made capture work on macOS.

We captured the Windows USB traffic and reproduced its UVC **Probe/Commit negotiation** before opening AVFoundation. This allowed the camera to start directly on the Mac, without using Windows first.

The minimum negotiation sequence required by this camera and the cause of the incompatibility remain unknown.

## Tested hardware and system

| Component | Tested configuration |
| --- | --- |
| Camera | RF4 RF-4KC7 |
| USB identity | `0ac8:3420`, device revision `0x0409`; USB product name `HiCamera` |
| Video profile | UVC 1.10, MJPEG, 3840 × 2160, nominal 30 fps |
| Mac | Apple M5 Pro, hardware model `Mac17,9`, `arm64` |
| macOS | 26.6.2 |

The final executable was tested after a camera power cycle, followed by **90 frames received through FFmpeg/AVFoundation at 3840 × 2160**. A second initialization attempt during capture was refused, and capture continued normally.

Binaries target **Apple Silicon (`arm64`)**. Validation covers only the camera revision and system configuration listed above.

## Usage

1. Connect the camera's 12 V power supply and USB cable to the Mac.
2. Close all applications using the camera, including existing previews or recordings.
3. Run `rf4`.
4. Open your capture application and select **3840 × 2160 at 30 fps**.

Run the initializer after each power-on or USB reconnection, before starting capture.

### Binary archive

The CI workflow packages the executable as `rf4-macos-arm64.tar.gz`. Extract the archive and initialize the camera:

```sh
tar -xzf rf4-macos-arm64.tar.gz
./rf4
```

The binary is **ad hoc signed** and lacks Apple notarization. macOS may display a security warning when you open a downloaded copy.

### Selecting a camera

With no arguments, `rf4` requires exactly one matching camera. If several are connected, list their USB location IDs and select one explicitly:

```sh
./rf4 --list
./rf4 --device 0x01100000
```

Replace the example ID with one reported by `--list`. Listing is read-only.

```sh
./rf4 --help
```

### Build from source

Building requires a macOS Swift 6 or newer toolchain. The commands below build for Apple Silicon (`arm64`):

```sh
swift build --configuration release --arch arm64
bin_dir="$(swift build --configuration release --arch arm64 --show-bin-path)"
"$bin_dir/rf4"
```

## Safety and limitations

- Initialization is refused if the camera is already streaming or does not match the supported USB/video profile.
- An advisory lock prevents concurrent initialization by `rf4` instances for the same camera and user. Keep capture applications closed until initialization finishes.
- The program does not detach the UVC driver, reset the USB device, or write firmware.
- If negotiation fails partway through, Probe parameters may already have changed. The program stops and reports the error.
- This camera was observed to keep sending 4K even when a lower resolution was requested. Use **3840 × 2160 at 30 fps** in the capture application to avoid a resolution mismatch.

Exit status: `0` for success, `1` for a runtime error, and `2` for invalid arguments.
