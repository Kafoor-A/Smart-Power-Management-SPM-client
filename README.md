
# 🚀 Project Title: Smart-Power-Management-SPM-client
![image](https://github.com/user-attachments/assets/45b09922-4006-460a-9252-0c3c656dd30a)

## 📌 Overview
A smart power management system using ESP32 for real-time monitoring and automatic switching between primary and backup power sources. It features load balancing, overcurrent protection, and is ideal for smart homes and IoT-based microgrid applications.

## 🧠 Key Features
- ✅ Real-time tracking / smart control
- ✅ Real-time power monitoring and logging
- ✅ Automatic source switching based on thresholds
- ✅ Intelligent load balancing
- ✅ Overcurrent protection

## 🛠️ Technologies Used

### 💻 Frontend
![Flutter](https://img.shields.io/badge/Frontend-Flutter-02569B?logo=flutter&logoColor=white)

### 🗄️ Database
![Firebase](https://img.shields.io/badge/Database-Firebase-FFCA28?logo=firebase&logoColor=black)

### ⚙️ Hardware (if applicable)
![ESP32](https://img.shields.io/badge/Hardware-ESP32-000000?logo=espressif&logoColor=white)


## 🧩 Available Platforms
- 📱 Android
- 🚀 Embedded (ESP32)

## ⚙️ System Architecture
> _Using bluetooth it can Config and Tranfer Data to android APP ._
```mermaid
graph TD
  User -->|UI Input| Frontend
  Frontend -->|API Calls| Backend
  Backend -->|Query| Database
  Backend -->|Control Signals| Hardware
  Hardware -->|Sensor Data| Backend
```

## 📸 Screenshots / Demo

| Mobile View | Hardware Setup |
|-------------|----------------|
| ![WhatsApp Image 2025-05-19 at 05 58 46_a3684c5b](https://github.com/user-attachments/assets/462ef1dd-13f0-4a0c-a422-5418b4f7ffe2)| ![Untitled design](https://github.com/user-attachments/assets/7ae57776-54d8-4d40-8fbc-0c0e4b944ef5)|



## 📱 Installation & Setup

### Prerequisites
- [ ] Flutter SDK 
- [ ] Android Studio

### Setup Steps
```bash
# Clone the repository
git clone https://github.com/Raghavan2005/Smart-Power-Management-SPM-client.git
cd Smart-Power-Management-SPM-client

# Install dependencies
flutter pub get     # For Flutter frontend

# Run the Flutter app
flutter run
```

## 📄 License
This project is licensed under the [MIT License](LICENSE).
