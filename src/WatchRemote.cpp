#include "WatchRemote.h"

#include <Arduino.h>
#include <NimBLEDevice.h>

#include <array>
#include <cstring>
#include <string>

namespace watchremote {

namespace {

constexpr char kDeviceName[] = "X4 Watch Remote";
constexpr size_t kQueueCapacity = 8;

NimBLEServer* g_server = nullptr;
NimBLECharacteristic* g_commandCharacteristic = nullptr;
NimBLECharacteristic* g_readerStateCharacteristic = nullptr;
NimBLECharacteristic* g_bookTitleCharacteristic = nullptr;
volatile bool g_running = false;
volatile bool g_connected = false;

constexpr size_t kStatePayloadSize = 16;
std::array<uint8_t, kStatePayloadSize> g_lastState = {};
bool g_hasState = false;
uint16_t g_titleRevision = 0;
char g_lastTitle[64] = {};

Command g_queue[kQueueCapacity] = {};
volatile uint8_t g_queueHead = 0;
volatile uint8_t g_queueTail = 0;
portMUX_TYPE g_queueMux = portMUX_INITIALIZER_UNLOCKED;

bool enqueue(const Command command) {
  bool accepted = false;
  portENTER_CRITICAL(&g_queueMux);
  const uint8_t next = static_cast<uint8_t>((g_queueHead + 1) % kQueueCapacity);
  if (next != g_queueTail) {
    g_queue[g_queueHead] = command;
    g_queueHead = next;
    accepted = true;
  }
  portEXIT_CRITICAL(&g_queueMux);
  return accepted;
}

class CommandCallbacks final : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* characteristic, NimBLEConnInfo& /*connInfo*/) override {
    const std::string value = characteristic->getValue();
    if (value.empty()) return;

    Command command = Command::None;
    switch (static_cast<uint8_t>(value.front())) {
      case static_cast<uint8_t>(Command::NextPage):
      case 'N':
      case 'n':
        command = Command::NextPage;
        break;
      case static_cast<uint8_t>(Command::PreviousPage):
      case 'P':
      case 'p':
        command = Command::PreviousPage;
        break;
      default:
        return;
    }

    enqueue(command);
  }
};

class ServerCallbacks final : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* /*server*/, NimBLEConnInfo& /*connInfo*/) override { g_connected = true; }

  void onDisconnect(NimBLEServer* /*server*/, NimBLEConnInfo& /*connInfo*/, int /*reason*/) override {
    g_connected = false;
    if (g_running) NimBLEDevice::startAdvertising();
  }
};

CommandCallbacks g_commandCallbacks;
ServerCallbacks g_serverCallbacks;

void clearQueue() {
  portENTER_CRITICAL(&g_queueMux);
  g_queueHead = 0;
  g_queueTail = 0;
  portEXIT_CRITICAL(&g_queueMux);
}

uint16_t titleRevision(const char* title) {
  // FNV-1a folded to 16 bits. This is a change token, not an identity or a
  // cryptographic hash; a collision only delays a title refresh until reconnect.
  uint32_t hash = 2166136261u;
  if (title) {
    for (const auto* p = reinterpret_cast<const uint8_t*>(title); *p; ++p) {
      hash ^= *p;
      hash *= 16777619u;
    }
  }
  return static_cast<uint16_t>(hash ^ (hash >> 16));
}

void writeU32(std::array<uint8_t, kStatePayloadSize>& payload, const size_t offset, const uint32_t value) {
  payload[offset] = static_cast<uint8_t>(value & 0xFFu);
  payload[offset + 1] = static_cast<uint8_t>((value >> 8) & 0xFFu);
  payload[offset + 2] = static_cast<uint8_t>((value >> 16) & 0xFFu);
  payload[offset + 3] = static_cast<uint8_t>((value >> 24) & 0xFFu);
}

}  // namespace

bool begin() {
  if (g_running) return true;
  if (!NimBLEDevice::isInitialized()) return false;

  g_server = NimBLEDevice::createServer();
  if (!g_server) return false;
  g_server->setCallbacks(&g_serverCallbacks, false);

  NimBLEService* service = g_server->createService(kServiceUuid);
  if (!service) return false;

  g_commandCharacteristic = service->createCharacteristic(
      kCommandCharacteristicUuid, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
  if (!g_commandCharacteristic) return false;
  g_commandCharacteristic->setCallbacks(&g_commandCallbacks);

  g_readerStateCharacteristic = service->createCharacteristic(
      kReaderStateCharacteristicUuid, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
  if (!g_readerStateCharacteristic) return false;

  g_bookTitleCharacteristic = service->createCharacteristic(kBookTitleCharacteristicUuid, NIMBLE_PROPERTY::READ);
  if (!g_bookTitleCharacteristic) return false;

  const std::array<uint8_t, kStatePayloadSize> emptyState = {};
  g_readerStateCharacteristic->setValue(emptyState.data(), emptyState.size());
  g_bookTitleCharacteristic->setValue("");
  g_hasState = false;
  g_titleRevision = 0;
  g_lastTitle[0] = '\0';

  NimBLEAdvertising* advertising = NimBLEDevice::getAdvertising();
  if (!advertising) return false;
  advertising->setName(kDeviceName);
  advertising->addServiceUUID(kServiceUuid);
  advertising->enableScanResponse(true);

  clearQueue();
  g_connected = false;
  g_running = advertising->start();
  return g_running;
}

void end() {
  if (!g_running) return;
  NimBLEAdvertising* advertising = NimBLEDevice::getAdvertising();
  if (advertising && advertising->isAdvertising()) advertising->stop();

  g_running = false;
  g_connected = false;
  g_commandCharacteristic = nullptr;
  g_readerStateCharacteristic = nullptr;
  g_bookTitleCharacteristic = nullptr;
  g_server = nullptr;
  clearQueue();
}

bool isRunning() { return g_running; }

bool isConnected() { return g_connected; }

void updateReaderState(const uint8_t readerType, const char* title, const uint32_t currentPage,
                       const uint32_t totalPages, const uint8_t progressPercent, const uint8_t batteryPercent) {
  if (!g_running || !g_readerStateCharacteristic || !g_bookTitleCharacteristic) return;

  const char* safeTitle = title ? title : "";
  const uint16_t revision = titleRevision(safeTitle);
  if (revision != g_titleRevision || std::strncmp(g_lastTitle, safeTitle, sizeof(g_lastTitle) - 1) != 0) {
    std::strncpy(g_lastTitle, safeTitle, sizeof(g_lastTitle) - 1);
    g_lastTitle[sizeof(g_lastTitle) - 1] = '\0';
    g_titleRevision = revision;
    g_bookTitleCharacteristic->setValue(reinterpret_cast<const uint8_t*>(g_lastTitle), std::strlen(g_lastTitle));
  }

  std::array<uint8_t, kStatePayloadSize> payload = {};
  payload[0] = 1;  // Protocol version.
  payload[1] = readerType;
  payload[2] = readerType == 0 ? 0 : 1;  // Bit 0: a reader is active.
  payload[3] = progressPercent;
  payload[4] = batteryPercent;
  payload[5] = 0;  // Reserved.
  writeU32(payload, 6, currentPage);
  writeU32(payload, 10, totalPages);
  payload[14] = static_cast<uint8_t>(revision & 0xFFu);
  payload[15] = static_cast<uint8_t>((revision >> 8) & 0xFFu);

  if (g_hasState && payload == g_lastState) return;
  g_lastState = payload;
  g_hasState = true;
  g_readerStateCharacteristic->setValue(payload.data(), payload.size());
  if (g_connected) g_readerStateCharacteristic->notify();
}

bool popCommand(Command& command) {
  bool available = false;
  portENTER_CRITICAL(&g_queueMux);
  if (g_queueTail != g_queueHead) {
    command = g_queue[g_queueTail];
    g_queueTail = static_cast<uint8_t>((g_queueTail + 1) % kQueueCapacity);
    available = true;
  }
  portEXIT_CRITICAL(&g_queueMux);
  return available;
}

}  // namespace watchremote
