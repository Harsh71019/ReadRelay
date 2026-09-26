#pragma once

#include <cstdint>

namespace watchremote {

// Stable protocol identifiers shared with the watchOS app.
inline constexpr const char* kServiceUuid = "F8A10001-7B4A-4C8B-9C61-4B5D6A731001";
inline constexpr const char* kCommandCharacteristicUuid = "F8A10002-7B4A-4C8B-9C61-4B5D6A731001";
inline constexpr const char* kReaderStateCharacteristicUuid = "F8A10003-7B4A-4C8B-9C61-4B5D6A731001";
inline constexpr const char* kBookTitleCharacteristicUuid = "F8A10004-7B4A-4C8B-9C61-4B5D6A731001";

enum class Command : uint8_t {
  None = 0x00,
  NextPage = 0x01,
  PreviousPage = 0x02,
};

// Start a small BLE GATT server after NimBLE has been initialized by the existing
// CrossPoint BLE lifecycle. The Apple Watch acts as the central and writes one-byte
// commands to kCommandCharacteristicUuid.
bool begin();

// Stop advertising and forget pointers owned by NimBLE before the host stack is
// deinitialized by BleKeyboardHost.
void end();

bool isRunning();
bool isConnected();

// Publish the reader snapshot exposed to companion remotes. The fixed state
// payload stays within the default 20-byte ATT notification limit; the title is
// a separate readable characteristic so long UTF-8 names can use a GATT long read.
// readerType matches ScreenshotInfo::ReaderType (0 none, 1 EPUB, 2 TXT, 3 XTC).
void updateReaderState(uint8_t readerType, const char* title, uint32_t currentPage, uint32_t totalPages,
                       uint8_t progressPercent, uint8_t batteryPercent);

// Thread-safe handoff from NimBLE's callback task to CrossPoint's main loop.
bool popCommand(Command& command);

}  // namespace watchremote
