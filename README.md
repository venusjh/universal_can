# Universal CAN Communication Package

Flutter 환경에서 USB Serial 및 Bluetooth를 통해 커스텀 16바이트 바이너리 프로토콜 기반의 CAN 통신을 수행할 수 있도록 지원하는 패키지입니다.

---

## 지원 환경 (Requirements)
- **Flutter:** >= 3.3.0
- **Dart:** >= 3.11.4
- **Platform:** Android (Bluetooth 등 하드웨어 통신 지원)

## 패키지 구조 및 아키텍처

이 패키지는 역할에 따라 명확하게 계층이 분리되어 있습니다.

1. **Client (`/client`)**
    - `CanClient` / `CanTransport`: 상위 클라이언트와 하위 통신 채널이 지켜야 할 공통 인터페이스
    - `CanProtocolClient`: CAN 연결 명령, 필터 설정, 데이터 송수신 및 파서 연동을 총괄하는 코어 컨트롤러
    - `SerialCanClient` / `BluetoothCanClient`: USB Serial 및 Bluetooth 하드웨어 통로를 구현한 실무 클라이언트
2. **Model (`/model`)**
    - `CanDataPackType`: 16바이트 수신 Raw 데이터를 객체로 변환하는 파싱 모델
    - `CanSendFrameType`: 전송할 CAN 데이터를 16바이트 바이너리 배열로 직렬화하는 모델
    - 각종 Enum (`CanSendCommand`, `CanBaudRate`, `CanBusMode` 등)
3. **Parser (`/parser`)**
    - `CanParser`: 수신 바이트 스트림을 버퍼링하고, 16바이트 단위로 잘라낸 뒤 CRC-8 검증 및 타임스탬프를 계산하는 파서
    - `Crc8`: 룩업 테이블 기반의 무결성 검사 체크섬 유틸리티

---

## 주요 기능 및 사용 방법

### 1. 클라이언트 초기화 및 연결 (USB Serial 예시)
```
// USB Serial 기반 클라이언트 생성
final canClient = SerialCanClient();

// 1. 하드웨어 물리적 연결 (예: USB 포트 오픈)
bool isConnected = await canClient.connect();
if (isConnected) {
  print('기기 연결 성공!');
}

// 2. CAN 버스 통신 시작 (채널 0, 125kbps, Normal 모드)
await canClient.connectCan(
  channel: 0,
  baudRate: CanBaudRate.cb125k,
  busMode: CanBusMode.cbmNormal,
);
```

### 2. 수신 데이터 스트림(Stream) 구독
파싱이 완료된 `CanDataPackType` 프레임을 실시간으로 받아 처리할 수 있습니다.
```
canClient.frames.listen((packet) {
  print('수신된 CAN ID: 0x${packet.id.toRadixString(16)}');
  print('채널: ${packet.channel}, 데이터 길이: ${packet.dlc}');
  print('페이로드 데이터: ${packet.data}');
});
```

### 3. CAN 메시지 송신
```
// 8바이트 페이로드 데이터 준비
final payload = Uint8List.fromList([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]);

// 지정한 CAN ID로 메시지 전송
await canClient.sendCanFrame(
  0x123, // CAN ID
  payload,
  channel: 0,
  isExtended: true, // 29비트 확장 아이디 여부
);
```

### 4. CAN ID 필터링 설정
특정 ID의 메시지만 수신하도록 필터를 걸 수 있습니다.
```
// 채널 0번에서 0x123, 0x456 ID만 수신 허용
canClient.setCanIdFilter(0, {0x123, 0x456});
```

### 5. 연결 해제 및 자원 정리
```
// CAN 통신 중지
await canClient.disconnectCan(channel: 0);

// 하드웨어 연결 해제 및 리소스 반환
await canClient.disconnect();
await canClient.dispose();
```
