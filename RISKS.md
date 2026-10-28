# RISKS / BLOCKERS
| ID | Risk | Impact | Status / mitigation |
|---|---|---|---|
| R1 | **No Android device or emulator** | Cannot verify launch, touch, FPS, thermals on hardware | BLOCKER for perf acceptance. Emulator installed and checked: `emulator -accel-check` → "KVM requires a CPU that supports vmx or svm" (container CPU exposes no virtualisation; x86/arm images cannot boot without it). Options: physical device over `adb` (e.g. from a local machine with the APK), or Firebase Test Lab via `gcloud` (installed, needs a logged-in GCP account with Test Lab enabled), or BrowserStack/Sauce. |
| R2 | Draw calls 265 on scene with primitives | Low-end GPUs | Palette atlas + shared material; merge static town meshes (next) |
| R3 | Screenshots rendered with software Vulkan (lavapipe) | Colour/perf not representative of devices | Use only for layout/readability review |
| R4 | One-day deadline vs asset volume | Scope | Batch pipeline, parametric generators, primitive fallback |
| R5 | Mixed-source art inconsistency | Visual quality | Mandatory re-palette pipeline + contact-sheet review |
| R6 | Package id / release keystore not final | Store submission | Decide before Phase 4 |
