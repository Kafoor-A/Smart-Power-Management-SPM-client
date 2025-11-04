#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>
#include <BLE2902.h>

// BLE Service & Characteristic UUIDs
#define SERVICE_UUID        "12345678-1234-1234-1234-1234567890ab"
#define CHARACTERISTIC_UUID "abcdefab-1234-1234-1234-abcdefabcdef"

// Pin configuration
const int relayPin = 26;
const int buzzerPin = 27;
const int ledPin = 25;
const int loadSwitchPin = 33;

const unsigned long delayBeforeOff = 5000;

bool generatorOn = false;
unsigned long lastLowStartTime = 0;

BLECharacteristic *pCharacteristic;
bool deviceConnected = false;

class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    deviceConnected = true;
    Serial.println("BLE Device Connected");
  }

  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
    Serial.println(" BLE Device Disconnected");
  }
};

void sendBLEMessage(String msg) {
  if (deviceConnected) {
    pCharacteristic->setValue(msg.c_str());
    pCharacteristic->notify();
  }
  Serial.println(msg);  // still print to serial
}

void setup() {
  Serial.begin(115200);
  pinMode(relayPin, OUTPUT);
  pinMode(buzzerPin, OUTPUT);
  pinMode(ledPin, OUTPUT);
  pinMode(loadSwitchPin, INPUT_PULLUP);

  digitalWrite(relayPin, LOW);
  digitalWrite(buzzerPin, LOW);
  digitalWrite(ledPin, LOW);

  // BLE Setup
  BLEDevice::init("ESP32-Generator");
  BLEServer *pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);
  pCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID,
                      BLECharacteristic::PROPERTY_NOTIFY |
                      BLECharacteristic::PROPERTY_READ
                    );
  pCharacteristic->addDescriptor(new BLE2902());
  pService->start();
  pServer->getAdvertising()->start();

  sendBLEMessage(" System Initialized - BLE Ready");
}

void loop() {
  bool loadSimulated = digitalRead(loadSwitchPin) == LOW;

  sendBLEMessage("Load: " + String(loadSimulated ? "HIGH" : "LOW"));
  if (loadSimulated && millis() % 10000 < 1000) {
    digitalWrite(buzzerPin, HIGH);
    digitalWrite(ledPin, HIGH);
    digitalWrite(relayPin, LOW);
    generatorOn = false;
    sendBLEMessage("Overload! Buzzer+LED ON, Generator OFF.");
    delay(1000);
    return;
  } else {
    digitalWrite(buzzerPin, LOW);
    digitalWrite(ledPin, LOW);
  }

  if (loadSimulated && !generatorOn) {
    digitalWrite(relayPin, HIGH);
    generatorOn = true;
    sendBLEMessage(" Generator ON due to load.");
  }

  if (!loadSimulated && generatorOn) {
    if (lastLowStartTime == 0) {
      lastLowStartTime = millis();
      sendBLEMessage("⏳ Low load detected. Shutdown timer started.");
    } else if (millis() - lastLowStartTime >= delayBeforeOff) {
      digitalWrite(relayPin, LOW);
      generatorOn = false;
      lastLowStartTime = 0;
      sendBLEMessage("Generator OFF after delay.");
    } else {
      sendBLEMessage(" Waiting... " + String(millis() - lastLowStartTime) + " ms");
    }
  } else {
    lastLowStartTime = 0;
  }

  sendBLEMessage("Generator: " + String(generatorOn ? "ON" : "OFF"));
  sendBLEMessage(" Buzzer: " + String(digitalRead(buzzerPin) ? "ON" : "OFF"));
  sendBLEMessage(" LED: " + String(digitalRead(ledPin) ? "ON" : "OFF"));
  sendBLEMessage("--------------------------------------------------");

  delay(3000);
}
