#include <ESP8266WiFi.h>
#include <ESP8266HTTPClient.h>
#include <WiFiClientSecure.h>

// ========================================
// 🔧 CHANGE THESE VALUES BEFORE UPLOADING
// ========================================
const char* WIFI_SSID = "YOUR_WIFI_NAME";        // ← Change this!
const char* WIFI_PASS = "YOUR_WIFI_PASSWORD";    // ← Change this!
const int BIN_ID = 2;                             // ← Your bin ID from dashboard
const int BIN_HEIGHT_CM = 100;                    // ← Your bin height in cm
// ========================================

// Pin Configuration
#define TRIG_PIN D1      // Ultrasonic Trigger → GPIO5
#define ECHO_PIN D2      // Ultrasonic Echo → GPIO4
#define MOISTURE_PIN A0  // Moisture sensor analog pin

// API Configuration
const char* API_URL = "https://smartbin.pythonanywhere.com/add_garbage_data/";
const int UPDATE_INTERVAL = 30000;  // 30 seconds (change to 300000 for 5 minutes)

void setup() {
  // Initialize Serial Monitor
  Serial.begin(115200);
  delay(1000);
  Serial.println("\n\n");
  Serial.println("╔════════════════════════════════════╗");
  Serial.println("║     🗑️  SmartBin Hardware v1.0    ║");
  Serial.println("╚════════════════════════════════════╝");
  
  // Setup pins
  pinMode(TRIG_PIN, OUTPUT);
  pinMode(ECHO_PIN, INPUT);
  
  // Connect to WiFi
  connectWiFi();
  
  Serial.println("\n✅ Setup Complete! Starting measurements...\n");
}

void loop() {
  // Check WiFi connection
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("❌ WiFi disconnected! Reconnecting...");
    connectWiFi();
  }
  
  Serial.println("─────────────────────────────────────");
  
  // Read sensors
  int garbageLevel = measureGarbageLevel();
  bool isMoisture = checkMoisture();
  
  // Send data to API
  sendDataToAPI(garbageLevel, isMoisture);
  
  Serial.println("─────────────────────────────────────");
  Serial.println("⏳ Waiting " + String(UPDATE_INTERVAL/1000) + " seconds...\n");
  
  // Wait before next reading
  delay(UPDATE_INTERVAL);
}

void connectWiFi() {
  Serial.println("\n📡 Connecting to WiFi: " + String(WIFI_SSID));
  
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 30) {
    delay(500);
    Serial.print(".");
    attempts++;
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\n✅ WiFi Connected!");
    Serial.println("📍 IP Address: " + WiFi.localIP().toString());
    Serial.println("📶 Signal Strength: " + String(WiFi.RSSI()) + " dBm");
  } else {
    Serial.println("\n❌ WiFi Connection Failed!");
    Serial.println("⚠️  Check SSID and Password");
  }
}

int measureGarbageLevel() {
  Serial.println("📏 Measuring garbage level...");
  
  // Clear trigger pin
  digitalWrite(TRIG_PIN, LOW);
  delayMicroseconds(2);
  
  // Send 10us pulse
  digitalWrite(TRIG_PIN, HIGH);
  delayMicroseconds(10);
  digitalWrite(TRIG_PIN, LOW);
  
  // Read echo pulse (timeout after 30ms)
  long duration = pulseIn(ECHO_PIN, HIGH, 30000);
  
  if (duration == 0) {
    Serial.println("⚠️  Ultrasonic sensor timeout!");
    return 0;
  }
  
  // Calculate distance in cm
  float distance = (duration * 0.0343) / 2;
  
  // Calculate garbage level (distance from sensor to garbage)
  int garbageLevel = BIN_HEIGHT_CM - (int)distance;
  
  // Ensure valid range
  if (garbageLevel < 0) garbageLevel = 0;
  if (garbageLevel > BIN_HEIGHT_CM) garbageLevel = BIN_HEIGHT_CM;
  
  Serial.println("   Distance from sensor: " + String((int)distance) + " cm");
  Serial.println("   ✅ Garbage Level: " + String(garbageLevel) + " cm");
  Serial.println("   📊 Fill Percentage: " + String((garbageLevel * 100) / BIN_HEIGHT_CM) + "%");
  
  return garbageLevel;
}

bool checkMoisture() {
  Serial.println("💧 Checking moisture...");
  
  int moistureValue = analogRead(MOISTURE_PIN);
  
  // Adjust threshold based on your sensor (typically 300-600)
  // Lower value = more moisture detected
  bool isWet = (moistureValue > 512);
  
  Serial.println("   Sensor Value: " + String(moistureValue));
  Serial.println("   ✅ Status: " + String(isWet ? "WET 💦" : "DRY ☀️"));
  
  return isWet;
}

void sendDataToAPI(int garbageLevel, bool moistureStatus) {
  Serial.println("📤 Sending data to SmartBin API...");
  
  // Create secure WiFi client
  WiFiClientSecure client;
  client.setInsecure();  // Skip SSL certificate verification
  
  HTTPClient http;
  
  // Prepare JSON payload
  String jsonPayload = "{";
  jsonPayload += "\"bin_id\":" + String(BIN_ID) + ",";
  jsonPayload += "\"garbage_level\":" + String(garbageLevel) + ",";
  jsonPayload += "\"moisture_status\":" + String(moistureStatus ? "true" : "false");
  jsonPayload += "}";
  
  Serial.println("   JSON: " + jsonPayload);
  
  // Send POST request
  http.begin(client, API_URL);
  http.addHeader("Content-Type", "application/json");
  
  int httpResponseCode = http.POST(jsonPayload);
  
  // Handle response
  if (httpResponseCode > 0) {
    String response = http.getString();
    
    if (httpResponseCode == 200) {
      Serial.println("   ✅ SUCCESS! Data sent to dashboard");
      Serial.println("   Response: " + response);
    } else {
      Serial.println("   ⚠️  Server returned code: " + String(httpResponseCode));
    }
  } else {
    Serial.println("   ❌ Error sending data!");
    Serial.println("   Error code: " + String(httpResponseCode));
    
    // Common error codes
    if (httpResponseCode == -1) {
      Serial.println("   → Check internet connection");
    } else if (httpResponseCode == -11) {
      Serial.println("   → SSL connection failed (will retry)");
    }
  }
  
  http.end();
}
