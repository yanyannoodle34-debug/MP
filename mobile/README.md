# MoneyPrinterMobile — Android Local App

AI-powered short video generator that runs **entirely on-device** on Android.

## Pipeline (all local except API calls)

```
Topic (text)
  → LLM API  (script + search terms)
  → Pexels API  (download stock clips to device)
  → flutter_tts  (on-device TTS → WAV audio)
  → ffmpeg_kit  (concat clips + burn audio + subtitles → MP4)
  → Save to gallery / Share
```

## Prerequisites

| What | Where to get |
|------|-------------|
| Flutter SDK ≥ 3.2 | [flutter.dev](https://flutter.dev) |
| Android device / emulator ≥ API 24 (Android 7) | — |
| LLM API key | [openrouter.ai/keys](https://openrouter.ai/keys) — free tier available |
| Pexels API key | [pexels.com/api](https://www.pexels.com/api/) — free |

## Getting started

```bash
cd mobile
flutter pub get
flutter run                      # debug build on connected Android device
flutter build apk --release      # release APK → build/app/outputs/flutter-apk/
```

## First run

1. Tap the ⚙ Settings icon (top-right).
2. Paste your **OpenRouter API key** and choose a model (default: `openai/gpt-4o-mini`).
3. Paste your **Pexels API key**.
4. Save settings.
5. Enter a topic on the home screen and tap **Generate Video**.

## Architecture

```
lib/
├── main.dart                  # App entry
├── models/
│   ├── app_config.dart        # User settings model
│   └── video_task.dart        # Task / progress state
├── services/
│   ├── llm_service.dart       # OpenAI-compatible API → script + terms
│   ├── material_service.dart  # Pexels search + download clips
│   ├── tts_service.dart       # flutter_tts → WAV file on-device
│   ├── subtitle_service.dart  # SRT generation (timing by char count)
│   └── video_service.dart     # ffmpeg_kit orchestration → MP4
├── providers/
│   └── app_provider.dart      # ChangeNotifier wiring all services
└── screens/
    ├── home_screen.dart        # Topic input + suggestions
    ├── generate_screen.dart    # Progress steps + live log
    ├── preview_screen.dart     # Chewie video player + save/share
    └── settings_screen.dart   # API keys, TTS, duration config
```

## LLM providers

Any OpenAI-compatible endpoint works. Change the base URL in Settings:

| Provider | Base URL | Notes |
|----------|----------|-------|
| OpenRouter | `https://openrouter.ai/api/v1` | Default; many free models |
| Anthropic | `https://api.anthropic.com/v1` | Use Claude model IDs |
| Local (Ollama) | `http://10.0.2.2:11434/v1` | `10.0.2.2` = host from emulator |

## Output

Videos are saved to:
`Android/data/com.moneyprinter.mobile/files/MoneyPrinterMobile/video_<timestamp>.mp4`

Use "Save to Gallery" in the preview screen to copy to your Photos/Gallery app.
