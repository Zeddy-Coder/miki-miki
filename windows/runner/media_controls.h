#ifndef RUNNER_MEDIA_CONTROLS_H_
#define RUNNER_MEDIA_CONTROLS_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

#include <memory>

// Posted to the main window when a system media button is pressed (WPARAM = button code).
// The system calls the handler on a worker thread, so the press is moved to the UI thread this way.
constexpr UINT kMediaButtonMessage = WM_APP + 0x31;

// Windows media controls (System Media Transport Controls): the play / pause / next / previous
// buttons of headphones and keyboards, and the system media overlay.
// Dart side: lib/services/media_controls.dart, channel "miki_miki/media_controls".
class MediaControls {
 public:
  MediaControls(HWND window, flutter::BinaryMessenger* messenger);
  ~MediaControls();

  MediaControls(const MediaControls&) = delete;
  MediaControls& operator=(const MediaControls&) = delete;

  // Called on the UI thread for kMediaButtonMessage.
  void HandleButtonMessage(WPARAM button);

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

#endif  // RUNNER_MEDIA_CONTROLS_H_
