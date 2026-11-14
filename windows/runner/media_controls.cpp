#include "media_controls.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <unknwn.h>

#include <string>
#include <utility>

#include <systemmediatransportcontrolsinterop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.h>
#include <winrt/Windows.Storage.Streams.h>

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using winrt::Windows::Media::MediaPlaybackStatus;
using winrt::Windows::Media::MediaPlaybackType;
using winrt::Windows::Media::SystemMediaTransportControls;
using winrt::Windows::Media::SystemMediaTransportControlsButton;
using winrt::Windows::Media::SystemMediaTransportControlsButtonPressedEventArgs;

// Button codes shared by the worker thread and the UI thread
enum ButtonCode : WPARAM { kPlay = 1, kPause = 2, kStop = 3, kNext = 4, kPrevious = 5 };

std::wstring Utf8ToWide(const std::string& text) {
  if (text.empty()) return std::wstring();
  int size = ::MultiByteToWideChar(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()), nullptr, 0);
  if (size <= 0) return std::wstring();
  std::wstring wide(static_cast<size_t>(size), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()), &wide[0], size);
  return wide;
}

std::string GetString(const EncodableMap& map, const char* key) {
  auto it = map.find(EncodableValue(key));
  if (it == map.end()) return std::string();
  const std::string* value = std::get_if<std::string>(&it->second);
  return value ? *value : std::string();
}

bool GetBool(const EncodableMap& map, const char* key) {
  auto it = map.find(EncodableValue(key));
  if (it == map.end()) return false;
  const bool* value = std::get_if<bool>(&it->second);
  return value ? *value : false;
}

}  // namespace

struct MediaControls::Impl {
  HWND window = nullptr;
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel;
  SystemMediaTransportControls smtc{nullptr};
  winrt::event_token pressed_token{};
  bool ready = false;
  std::string last_thumbnail;

  // Attaches the system controls to the window. A failure only disables the feature.
  void Init() {
    try {
      auto interop = winrt::get_activation_factory<SystemMediaTransportControls, ISystemMediaTransportControlsInterop>();
      winrt::check_hresult(interop->GetForWindow(window, winrt::guid_of<SystemMediaTransportControls>(), winrt::put_abi(smtc)));
      smtc.IsEnabled(false);
      HWND target = window;
      pressed_token = smtc.ButtonPressed(
          [target](SystemMediaTransportControls const&, SystemMediaTransportControlsButtonPressedEventArgs const& args) {
            WPARAM code = 0;
            switch (args.Button()) {
              case SystemMediaTransportControlsButton::Play: code = kPlay; break;
              case SystemMediaTransportControlsButton::Pause: code = kPause; break;
              case SystemMediaTransportControlsButton::Stop: code = kStop; break;
              case SystemMediaTransportControlsButton::Next: code = kNext; break;
              case SystemMediaTransportControlsButton::Previous: code = kPrevious; break;
              default: break;
            }
            if (code != 0) ::PostMessage(target, kMediaButtonMessage, code, 0);
          });
      ready = true;
    } catch (...) {
      ready = false;
    }
  }

  void Update(const EncodableMap& map) {
    if (!ready) return;
    try {
      const bool playing = GetBool(map, "playing");
      smtc.IsEnabled(true);
      smtc.IsPlayEnabled(true);
      smtc.IsPauseEnabled(true);
      smtc.IsStopEnabled(false);
      smtc.IsNextEnabled(GetBool(map, "hasNext"));
      smtc.IsPreviousEnabled(GetBool(map, "hasPrevious"));
      smtc.PlaybackStatus(playing ? MediaPlaybackStatus::Playing : MediaPlaybackStatus::Paused);

      auto updater = smtc.DisplayUpdater();
      updater.Type(MediaPlaybackType::Video);
      auto video = updater.VideoProperties();
      video.Title(winrt::hstring(Utf8ToWide(GetString(map, "title"))));
      video.Subtitle(winrt::hstring(Utf8ToWide(GetString(map, "subtitle"))));

      const std::string thumbnail = GetString(map, "thumbnail");
      // The type was just set, which resets the thumbnail: set it again every time
      if (!thumbnail.empty()) {
        try {
          winrt::Windows::Foundation::Uri uri{winrt::hstring(Utf8ToWide(thumbnail))};
          updater.Thumbnail(winrt::Windows::Storage::Streams::RandomAccessStreamReference::CreateFromUri(uri));
        } catch (...) {
          // A broken address only means no picture
        }
      }
      last_thumbnail = thumbnail;
      updater.Update();
    } catch (...) {
      // Never let the system overlay break playback
    }
  }

  void Clear() {
    if (!ready) return;
    try {
      smtc.PlaybackStatus(MediaPlaybackStatus::Closed);
      auto updater = smtc.DisplayUpdater();
      updater.ClearAll();
      updater.Update();
      smtc.IsEnabled(false);
      last_thumbnail.clear();
    } catch (...) {
    }
  }

  void Shutdown() {
    if (!ready) return;
    try {
      smtc.ButtonPressed(pressed_token);
      smtc.IsEnabled(false);
    } catch (...) {
    }
    ready = false;
  }
};

MediaControls::MediaControls(HWND window, flutter::BinaryMessenger* messenger) : impl_(new Impl()) {
  impl_->window = window;
  impl_->Init();

  impl_->channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "miki_miki/media_controls", &flutter::StandardMethodCodec::GetInstance());
  Impl* impl = impl_.get();
  impl_->channel->SetMethodCallHandler(
      [impl](const flutter::MethodCall<EncodableValue>& call, std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        if (call.method_name() == "update") {
          const EncodableMap* map = call.arguments() ? std::get_if<EncodableMap>(call.arguments()) : nullptr;
          if (map) impl->Update(*map);
          result->Success();
        } else if (call.method_name() == "clear") {
          impl->Clear();
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
}

MediaControls::~MediaControls() {
  if (impl_) {
    impl_->channel = nullptr;
    impl_->Shutdown();
  }
}

void MediaControls::HandleButtonMessage(WPARAM button) {
  const char* name = nullptr;
  switch (button) {
    case kPlay: name = "play"; break;
    case kPause: name = "pause"; break;
    case kStop: name = "stop"; break;
    case kNext: name = "next"; break;
    case kPrevious: name = "previous"; break;
    default: return;
  }
  if (impl_ && impl_->channel) {
    impl_->channel->InvokeMethod("button", std::make_unique<EncodableValue>(std::string(name)));
  }
}
