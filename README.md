<div align="center">

# 🧊 TailCraft

**포트포워딩 없이, 설치 하나로 여는 마인크래프트 서버 런처**
**A free Windows launcher that opens a Minecraft server in one click — no port forwarding.**

[다운로드 / Download](https://lapic121.github.io/tailcraft/) · [Ko-fi](https://ko-fi.com/sangdeok) · [Discord](https://discord.gg/rv5sH6RbS)

Windows 10 / 11 · 무료 (Free) · 한국어 · English

</div>

---

## 소개 / About

TailCraft는 친구와 마인크래프트 서버를 열 때 반복되는 일 — 공유기 포트포워딩, 자바 설치, 서버 파일 다운로드, 방화벽 설정 — 을 GUI 하나로 끝내는 런처입니다. EXE를 실행하면 창이 뜨고, 처음 켜면 **언어(한/영)를 고른 뒤 8단계 튜토리얼**이 서버 완성까지 안내합니다.

TailCraft is a GUI launcher that handles everything you normally repeat when hosting a Minecraft server for friends — router port forwarding, installing Java, downloading server files, firewall rules. Run the EXE, **pick your language (Korean/English)**, and an 8-step tutorial walks you through to a running server.

## 주요 기능 / Features

- **서버 종류 / Server types** — Paper · **Purpur** · **Folia** · Fabric · NeoForge · Forge · **Arclight** (모드 서버에서 Bukkit 플러그인까지 / run Bukkit plugins on a modded server). 버전·빌드 자동 로드, 필요한 Java(8/17/21/25) 자동 설치.
- **친구 접속 3가지 / 3 ways to connect** — Tailscale (포트포워딩 없이 / no port forwarding) · 포트포워딩 (UPnP 자동) · LAN. 방화벽 허용은 버튼 한 번.
- **실시간 대시보드 / Live dashboard** — CPU · RAM · 디스크 · 접속자, 램 할당 슬라이더.
- **모드·플러그인 / Mods & plugins** — Modrinth 검색·설치(의존성 자동), 활성/비활성 토글, 친구용 모드 zip 내보내기.
- **플레이어 관리 / Player tools** — 닉네임·IP 기록, 화이트리스트·OP·킥·밴 클릭 한 번.
- **콘솔·이벤트 로그·진단 / Console, event log, diagnostics** — 빠른 명령 버튼, 접속/퇴장/오류 이벤트 분리 보기, 원클릭 진단 복사.
- **한국어 / English UI** — 상단 버튼으로 즉시 전환.
- 국문·영문 네트워크 설정 가이드 PDF 동봉.

## 다운로드 / Download

👉 **https://lapic121.github.io/tailcraft/**

또는 [Releases](https://github.com/lapic121/tailcraft/releases/latest)에서 `TailCraft.zip`.

1. 압축 해제 후 `TailCraft.exe` 실행 / Unzip and run `TailCraft.exe`
2. 서명되지 않은 개인 배포라 SmartScreen 경고가 뜨면 **추가 정보 → 실행** / Unsigned build, so if SmartScreen warns: **More info → Run anyway**
3. 서버 파일·Java는 동봉하지 않고 **실행 시 공식 배포처에서 다운로드**됩니다. Minecraft EULA 동의 필요.

## 안전성 & 무결성 / Safety & integrity

이 저장소는 **소스 공개(source-available)** 입니다 — 누구나 코드를 열어 확인할 수 있습니다(라이선스는 아래 참고).

This repository is **source-available** — anyone can read and audit the code (see the license below).

- **제3자 파일 미동봉 / No bundled third-party files.** 서버 jar·Java·플러그인은 포함하지 않고, 사용자의 선택에 따라 실행 시점에 각 공식 배포처(PaperMC, FabricMC, NeoForged, Forge, Modrinth, Adoptium, Tailscale)에서만 다운로드합니다. 저작권자에게 어떤 정보도 전송하지 않습니다.
- **무결성 검증 / Integrity check.** 런처는 실행 시 번들된 `lib\core.ps1`의 SHA-256을 EXE에 내장된 값과 대조하여, 변조되면 실행을 거부합니다.
- **공식 해시 검증 / Verify your download.** 내려받은 EXE가 공식 배포본과 동일한지 확인하세요.

  ```
  TailCraft.exe  SHA-256:
  B0215D85E829FC1B8FA90EBCFEDBB175588965F4EFF97814281DD3B0F639DC27
  ```

  Windows (PowerShell 또는 cmd):
  ```
  certutil -hashfile TailCraft.exe SHA256
  ```
  출력이 위 값과 같으면 정품입니다. 다르면 공식 링크에서 다시 받으세요. / If it matches, it's authentic. If not, re-download from the official link.

## 소스에서 빌드 / Build from source

- 런처 본체: `launcher.ps1` + `lib/core.ps1` (PowerShell 5.1 / WPF)
- 단일 EXE 래퍼: `build/exe/main.go` (Go) — 스크립트를 내장·추출 후 숨김 콘솔로 실행. `go build` 시 스크립트 해시 검증 로직 포함.
- 설명서 PDF: `build/make_pdf.py`, `build/make_pdf_en.py` (reportlab)

## 라이선스 / License

**Copyright © 2026 Sangdeok. All rights reserved. — Source-available (NOT open source).**

소스는 열람·감사·학습을 위해 공개되지만, **수정·재배포·상업적 이용·코드 전용·무결성 우회는 금지**됩니다. 자세한 내용은 [`LICENSE.txt`](LICENSE.txt). 예외 허가가 필요하면 아래로 연락 주세요.

The source is published for reading, auditing and learning, but **modification, redistribution, commercial use, code reuse and bypassing the integrity check are not permitted**. See [`LICENSE.txt`](LICENSE.txt). Contact for exceptions.

## 비공식 고지 / Unofficial

TailCraft is not affiliated with, sponsored or endorsed by Mojang Studios, Microsoft, Tailscale Inc., PaperMC, FabricMC, NeoForged, Minecraft Forge, Arclight or Modrinth. "Minecraft" and "Tailscale" are trademarks of their respective owners; references are for compatibility only.

## 문의 / Contact

- Email: dwxw777@gmail.com
- Discord: [discord.gg/rv5sH6RbS](https://discord.gg/rv5sH6RbS) (sangdeok)
- 후원 / Support (optional): [ko-fi.com/sangdeok](https://ko-fi.com/sangdeok)
