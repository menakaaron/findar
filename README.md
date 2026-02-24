# Findar — AI Object Finder for the Visually Impaired (2026 WINFO Hackathon: Best Product Track)

Contributors: Harshita Keerthipati, Thanishkaa Saravanane, Menaka Aron, Tejaswi Erattu

An iOS app that helps visually impaired users find objects in their environment. Point your camera around the room, ask for an item by voice or text, and Findar tells you where it is — with spoken direction cues, distance estimates, and a 3D AR marker guiding you to it.

## Features

- **Passive scanning** — the app continuously indexes objects in view using on-device YOLOv8n, no user interaction required
- **Voice search** — speak naturally ("Where is my keys?") and the app extracts the target and begins searching
- **Text search** — type an object name to search the spatial index
- **Direction guidance** — receive hints like "on the couch, 2.5m from you" or "behind the desk, to your left"
- **AR marker** — a 3D green sphere is placed at the object's last known location in the real world
- **Haptic feedback** — pulse when the target object is centered on screen

## Tech Stack

| Layer | Technology |
|---|---|
| Language | Swift |
| UI | SwiftUI |
| AR / 3D | ARKit, RealityKit |
| Object Detection | CoreML + Vision framework |
| ML Model | YOLOv8n (80 COCO classes, on-device) |
| Voice Input | Speech framework, AVFoundation |
| Reactive State | Combine |

## How It Works

1. **Scan** — the camera feed is sampled every 10 frames; YOLOv8n runs inference and detected objects are stored in a spatial index with their 3D world coordinates via ARKit raycasting
2. **Search** — the user asks for an item by voice or text; the app queries the spatial index for the best match
3. **Navigate** — the app calculates the direction and distance to the object, generates a natural language hint referencing nearby landmarks (e.g. furniture), and places an AR marker at the location; direction updates in real time as the user moves

## Project Structure

```
Findar/vision/
  visionApp.swift          # App entry point, splash screen timer
  SplashView.swift         # Animated splash screen
  ContentView.swift        # Main UI — AR view, search bar, voice button, results card
  VisionNavigator.swift    # Core engine — AR session, ML inference, spatial index, search
  SpeechManager.swift      # Voice input, speech-to-text, command parsing
  yolov8n.mlpackage/       # CoreML model package (YOLOv8 nano, 6.2 MB)
```

## Getting Started

1. Open `Findar/vision.xcodeproj` in Xcode
2. Select your target device (physical iPhone recommended for AR)
3. Grant camera, microphone, and speech recognition permissions when prompted
4. Build and run

> Requires iOS with ARKit support. Speech recognition requires an internet connection on first use.
