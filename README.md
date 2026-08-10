# macOS Markdown Clipboard Formatter (실시간 마크다운 클립보드 변환기)

AI 챗봇(Gemini, ChatGPT, Claude 등)에서 복사한 마크다운(Markdown) 형식의 텍스트를 Apple Pages, Microsoft Word(Mac용), Apple Notes(메모) 등에 붙여넣을 때 서식이 깨지는 문제를 해결하는 **macOS 전용 실시간 클립보드 변환 유틸리티**입니다.

이 앱은 백그라운드에서 동작하는 순수 메뉴 막대(Menu Bar / Status Bar) 앱으로, 마크다운 텍스트를 실시간으로 감지하여 서식이 유지되는 HTML 및 RTF 리치 텍스트로 자동 변환합니다.

---

## 1. 주요 특징 (Core Features)

1. **실시간 백그라운드 감지**:
   - `NSPasteboard.changeCount`를 모니터링하여 CPU 사용률 거의 없이 실시간으로 클립보드 변경을 감지합니다.
2. **마크다운 휴리스틱 감지 (Auto-Detect)**:
   - 복사된 텍스트가 마크다운인지 자동으로 판단(제목, 리스트, 코드 블록, 볼드, 이탤릭, 링크 등의 패턴 분석)하고, 웹페이지 등에서 복사한 기존의 리치 텍스트 서식은 깨뜨리지 않고 그대로 보존합니다.
3. **무한 루프(Self-Trigger) 방지**:
   - 앱이 변환 결과를 클립보드에 다시 쓸 때 발생하는 이벤트를 감지하고 필터링할 수 있도록 커스텀 마커 타입(`org.markdown-formatter.marker`)을 클립보드에 할당하여 무한 변환 루프를 완벽하게 방지합니다.
4. **리치 텍스트 변환 및 호환성 극대화**:
   - HTML 데이터뿐만 아니라 `NSAttributedString`을 활용한 RTF(Rich Text Format) 데이터를 클립보드에 동시에 작성하여 Apple Pages, MS Word, Apple Notes 등 다양한 문서 편집기와의 복사-붙여넣기 호환성을 극대화합니다.
5. **구문 강조(Syntax Highlighting) 지원**:
   - 코드 블록(예: ` ```swift ... ``` `)을 복사할 경우, 다크 테마 기반의 CSS 스타일링과 정규식 토크나이저를 통해 주요 언어(Swift, Python, JavaScript, Java 등)의 키워드, 함수, 타입, 숫자, 문자열, 주석을 예쁘게 하이라이팅하여 서식을 그대로 복사합니다.
6. **메뉴 막대 전용 (UIElement)**:
   - Dock에 아이콘이 나타나지 않고, 메뉴 막대(Status Bar)에서만 깔끔하게 동작합니다.
   - 메뉴를 통해 자동 변환 켜기/끄기, 마크다운 감지 규칙 적용 여부, 변환 알림 설정, "지금 클립보드 즉시 변환" 수동 실행 및 종료 기능을 제공합니다.

---

## 2. 프로젝트 구조 (Directory Structure)

```text
markdown_agy/
├── Makefile                 # 빌드, 실행, 설치 자동화 스크립트
├── README.md                # 사용 가이드라인 (본 파일)
└── Sources/
    └── main.swift           # AppKit 기반 실시간 변환 유틸리티 전체 소스 코드
```

---

## 3. 빌드 및 실행 방법 (Build & Run Instructions)

Xcode 없이 macOS 터미널에서 `Makefile`을 이용해 즉시 빌드 및 실행할 수 있습니다.

### 1) 빌드 및 실행 (바로 시작하기)
프로젝트 폴더 내에서 다음 명령어를 실행하면 앱이 컴파일되고 백그라운드에서 바로 시작됩니다.
```bash
make run
```
*실행 시 메뉴 막대에 문서 모양의 아이콘(`📝` 또는 `doc.richtext` 심볼)이 나타납니다.*

### 2) 앱 종료하기
백그라운드에서 실행 중인 앱을 종료하려면 아래 명령어를 사용합니다.
```bash
make stop
```

### 3) 사용자 애플리케이션 폴더에 설치하기
맥에 영구적으로 설치하여 사용하려면 다음 명령어를 실행합니다. `~/Applications` 폴더로 `.app` 패키지가 설치되며 자동으로 실행됩니다.
```bash
make install
```

### 4) 빌드 아티팩트 청소
```bash
make clean
```

---

## 4. 권한 설정 및 샌드박스 가이드 (macOS System Security Guide)

이 앱은 macOS의 강력한 보안 정책(Gatekeeper 및 Sandboxing)을 준수하며, 로컬에서 실행할 때 다음 사안들을 참고해야 합니다.

### 1) 클립보드 접근 권한
* **Accessibility(손쉬운 사용) 권한 불필요**: 이 앱은 `NSPasteboard` API만을 이용해 클립보드를 제어하므로 별도의 Accessibility 권한이나 입력 모니터링 권한을 요청하지 않습니다.
* **샌드박스(Sandbox) 적용 시**: 만약 Xcode를 통해 App Store 배포용으로 샌드박스를 적용할 경우, 클립보드 읽기/쓰기가 기본 허용되므로 특별한 권한(Entitlement) 선언 없이 작동합니다.

### 2) 알림(Notification) 권한
* 앱을 처음 실행한 후 클립보드 변환이 발생하면 macOS에서 **알림 권한 허용 여부**를 묻는 팝업이 뜹니다.
* 허용해 주시면 변환이 완료될 때마다 우측 상단에 "Markdown Formatted" 토스트 알림이 표시됩니다. (메뉴 바에서 이 알림을 끌 수 있습니다.)

---

## 5. 잠재적 이슈 및 해결 방안 (Troubleshooting)

### 이슈 1: 다른 클립보드 관리 앱(Paste, Maccy, Clipy 등)과의 충돌
* **원인**: Maccy나 Paste 등은 클립보드 변경 내역(`changeCount`)을 감시하며 이전 복사 기록을 보관합니다. 우리 앱이 텍스트를 마크다운에서 리치 텍스트로 자동 재작성(Overwrite)할 때, 클립보드 관리 앱이 변환 전의 마크다운 텍스트와 변환 후의 리치 텍스트를 **2개의 별개 복사 기록**으로 중복 인식하여 히스토리에 쌓을 수 있습니다.
* **우회 방안**:
  1. **수동 변환 모드 활용**: 메뉴 바에서 **"Enable Automatic Formatting"**을 끄고, 필요할 때만 단축키처럼 메뉴에서 **"Format Clipboard Now" (Cmd+F)**를 눌러 수동으로 변환하면 히스토리가 꼬이는 현상을 피할 수 있습니다.
  2. **클립보드 관리자 제외 처리**: 대부분의 고급 클립보드 관리 앱(예: Paste, Maccy)은 특정 형식의 데이터가 포함된 복사본을 무시하는 기능이 있습니다. 우리 앱이 할당하는 커스텀 타입인 `org.markdown-formatter.marker`를 제외 필터(Ignore Types)로 등록해 두면 무시 처리가 가능합니다.

### 이슈 2: 변환을 원치 않는 일반 plain text가 리치 텍스트로 바뀌는 현상
* **원인**: "Auto-Detect Markdown Syntax" 옵션이 켜져 있어도 단순한 하이픈(-)이나 별표(*) 기호가 포함된 일반 메모 텍스트를 마크다운 목록(List) 문법으로 오인하여 서식 변환을 시도할 수 있습니다.
* **해결책**:
  * 마크다운이 아닌 단순 텍스트를 복사할 때는 일시적으로 메뉴 바 아이콘을 클릭해 **"Enable Automatic Formatting"**을 클릭하여 비활성화(체크 해제)하세요.
