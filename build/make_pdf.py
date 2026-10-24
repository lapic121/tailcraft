# -*- coding: utf-8 -*-
"""TailCraft 네트워크 설정 가이드 PDF 생성 (reportlab + Noto Sans CJK KR)"""
import sys
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.platypus import (SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle,
                                PageBreak, KeepTogether, ListFlowable, ListItem)
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont

OUT = sys.argv[1]
pdfmetrics.registerFont(TTFont('KR', 'build/fonts/NotoSansKR-400.ttf'))
pdfmetrics.registerFont(TTFont('KRB', 'build/fonts/NotoSansKR-700.ttf'))
pdfmetrics.registerFontFamily('KR', normal='KR', bold='KRB', italic='KR', boldItalic='KRB')

ACC = colors.HexColor('#2F6FD6'); MUT = colors.HexColor('#555'); BG = colors.HexColor('#F2F5FA'); WARN = colors.HexColor('#FFF4D6')
S = {
    'title': ParagraphStyle('t', fontName='KRB', fontSize=26, leading=34, textColor=ACC),
    'sub':   ParagraphStyle('s', fontName='KR', fontSize=12, leading=18, textColor=MUT),
    'h1':    ParagraphStyle('h1', fontName='KRB', fontSize=17, leading=24, textColor=ACC, spaceBefore=14, spaceAfter=6),
    'h2':    ParagraphStyle('h2', fontName='KRB', fontSize=13, leading=19, spaceBefore=10, spaceAfter=4),
    'p':     ParagraphStyle('p', fontName='KR', fontSize=10.5, leading=16.5, spaceAfter=5),
    'small': ParagraphStyle('sm', fontName='KR', fontSize=9, leading=13, textColor=MUT),
    'code':  ParagraphStyle('c', fontName='KR', fontSize=9.5, leading=14, backColor=BG, borderPadding=(4, 6, 4, 6), spaceBefore=3, spaceAfter=8),
    'box':   ParagraphStyle('b', fontName='KR', fontSize=10, leading=15, backColor=WARN, borderPadding=(6, 8, 6, 8), spaceBefore=4, spaceAfter=8),
    'th':    ParagraphStyle('th', fontName='KRB', fontSize=9.5, leading=13, textColor=colors.white),
    'td':    ParagraphStyle('td', fontName='KR', fontSize=9.5, leading=13),
}

def P(t, s='p'): return Paragraph(t, S[s])
def H1(t): return P(t, 'h1')
def H2(t): return P(t, 'h2')
def CODE(t): return P(t.replace('\n', '<br/>'), 'code')
def BOX(t): return P(t, 'box')
def UL(items):
    return ListFlowable([ListItem(P(i), leftIndent=12) for i in items], bulletType='bullet', start='•', leftIndent=14, bulletFontName='KR')
def OL(items):
    return ListFlowable([ListItem(P(i), leftIndent=14) for i in items], bulletType='1', leftIndent=16, bulletFontName='KR')
def TBL(head, rows, widths):
    data = [[Paragraph(h, S['th']) for h in head]] + [[Paragraph(c, S['td']) for c in r] for r in rows]
    t = Table(data, colWidths=widths, repeatRows=1)
    t.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), ACC), ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, BG]),
        ('GRID', (0, 0), (-1, -1), 0.4, colors.HexColor('#C9D2E0')),
        ('TOPPADDING', (0, 0), (-1, -1), 5), ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
    ]))
    t.spaceAfter = 8
    return t

def footer(c, d):
    c.saveState(); c.setFont('KR', 8.5); c.setFillColor(MUT)
    c.drawString(20 * mm, 12 * mm, 'TailCraft 네트워크 설정 가이드')
    c.drawRightString(A4[0] - 20 * mm, 12 * mm, f'{d.page}')
    c.restoreState()

doc = SimpleDocTemplate(OUT, pagesize=A4, leftMargin=20 * mm, rightMargin=20 * mm, topMargin=18 * mm, bottomMargin=20 * mm,
                        title='TailCraft 네트워크 설정 가이드', author='TailCraft')
F = []

# ---------------- 표지
F += [Spacer(1, 50 * mm), P('TailCraft', 'title'), P('마인크래프트 서버 네트워크 설정 가이드', 'sub'), Spacer(1, 6 * mm),
      P('테일스케일 | 포트포워딩 | LAN — 친구가 내 서버에 접속하게 만드는 모든 방법', 'sub'), Spacer(1, 60 * mm),
      P('이 문서는 런처의 "네트워크" 탭과 함께 보도록 만들어졌습니다. 각 장의 번호는 런처 튜토리얼 단계와 대응합니다.', 'small'), PageBreak()]

# ---------------- 목차
F += [H1('목차'), OL([
    '왜 네트워크 설정이 필요한가 (공유기와 NAT 이해하기)',
    '세 가지 방식 비교 — 무엇을 고를까',
    '방식 A: 테일스케일 (추천)',
    '방식 B: 포트포워딩',
    '방식 C: LAN 전용',
    'Windows 방화벽 (모든 방식 공통)',
    '친구에게 알려줄 것 / 접속 절차',
    '문제 해결 체크리스트',
    '보안 권장 사항',
    '부록: 포트 바꾸기, 공인 IP 변동, 공유기 2중 연결(이중 NAT)',
]), PageBreak()]

# ---------------- 1
F += [H1('1. 왜 네트워크 설정이 필요한가'),
      P('집 인터넷은 보통 <b>공유기(라우터)</b> 한 대가 통신사로부터 받은 <b>공인 IP 한 개</b>를 집 안의 여러 기기에 나눠 쓰게 해 줍니다. '
        '이때 집 안 기기들은 192.168.x.x 같은 <b>사설(내부) IP</b>를 받습니다. 이 구조를 NAT라고 합니다.'),
      P('문제는 <b>밖에서 안으로 들어오는 연결</b>입니다. 친구가 내 공인 IP로 접속을 시도하면 공유기는 "이 연결을 집 안 어느 PC로 보내야 하지?"를 모르기 때문에 그냥 버립니다. '
        '그래서 마인크래프트 서버를 열려면 아래 셋 중 하나를 해야 합니다.'),
      UL(['공유기에게 "25565번 포트로 오는 건 이 PC로 넘겨" 라고 알려주기 > <b>포트포워딩</b>',
          '공유기를 거치지 않는 가상 사설망(VPN)으로 친구와 직접 연결 > <b>테일스케일</b>',
          '아예 외부 접속을 포기하고 같은 공유기 안에서만 놀기 > <b>LAN</b>']),
      P('어느 방식이든 마지막에 <b>Windows 방화벽</b>이 서버 포트를 열어 줘야 합니다(6장). 이걸 빼먹어서 접속이 안 되는 경우가 가장 많습니다.'),
      ]

# ---------------- 2
F += [H1('2. 세 가지 방식 비교'),
      TBL(['항목', '테일스케일', '포트포워딩', 'LAN'], [
          ['공유기 설정', '불필요', '필요 (UPnP면 자동)', '불필요'],
          ['친구가 할 일', 'Tailscale 앱 설치 + 로그인', '없음 (주소만 입력)', '없음'],
          ['보안', '암호화 P2P, 외부에 포트 노출 없음', '포트가 인터넷에 공개됨 > 스캔·무작위 접속 위험', '외부 접근 불가'],
          ['지연/속도', '대부분 직접 연결(P2P). 일부 환경은 릴레이 경유로 약간 느림', '직접 연결, 가장 빠름', '가장 빠름'],
          ['인원 제한', '무료 플랜: 사용자 3명(기기 100대). 노드 공유로 우회 가능', '없음', '없음'],
          ['공인 IP 변동', '영향 없음', '바뀌면 친구에게 다시 알려야 함 (DDNS로 해결 가능)', '영향 없음'],
          ['기숙사·회사·LTE 등 포트 못 여는 환경', '가능', '불가', '-'],
      ], [28 * mm, 48 * mm, 52 * mm, 42 * mm]),
      BOX('<b>추천:</b> 친구가 10명 이하이고 공유기 설정이 번거롭다면 <b>테일스케일</b>. 불특정 다수에게 열거나 친구가 앱 설치를 싫어하면 <b>포트포워딩</b>. '
          'PC방·집에서 같은 와이파이로 놀 때는 <b>LAN</b>.'),
      PageBreak()]

# ---------------- 3 Tailscale
F += [H1('3. 방식 A: 테일스케일 (추천)'),
      P('테일스케일은 WireGuard 기반의 개인용 VPN 서비스입니다. 내 PC와 친구 PC에 각각 앱을 설치해 같은 "테일넷"에 넣으면, 서로 100.x.x.x 대역의 고정 IP로 직접 통신할 수 있습니다. '
        '공유기나 통신사가 뭐든 상관없고, 트래픽은 종단 간 암호화됩니다.'),
      H2('3-1. 서버 PC 설정 (런처 네트워크 탭)'),
      OL(['<b>[1. 테일스케일 설치]</b> 클릭 > 사용자 계정 컨트롤(UAC) 창에서 "예". 설치는 조용히 진행되며 1분 내외.',
          '<b>[2. 로그인 / 연결]</b> 클릭 > 브라우저가 열리면 Google / Microsoft / GitHub / Apple 계정 중 하나로 로그인. 처음이면 테일넷이 자동 생성됩니다.',
          '런처로 돌아와 <b>[상태 새로고침]</b>. 상태가 <b>연결됨</b>으로 바뀌고 <b>Tailscale IP</b>(100.x.x.x)와 <b>MagicDNS 이름</b>(예: desktop-abc.tail1234.ts.net)이 채워집니다.',
          '6장의 방화벽 규칙을 추가합니다.']),
      P('설치가 끝나면 작업 표시줄 트레이에 Tailscale 아이콘이 생깁니다. 아이콘을 눌러 "Connected" 상태인지 언제든 확인할 수 있습니다.', 'small'),
      H2('3-2. 친구 초대 — 두 가지 방법'),
      P('테일스케일은 "같은 테일넷(계정)에 속한 기기끼리만" 통신합니다. 그래서 친구를 들이는 방법은 둘 중 하나입니다: '
        '<b>(1) 친구를 내 테일넷의 사용자로 초대</b>하거나, <b>(2) 친구는 자기 테일넷을 쓰고 내 서버 PC 한 대만 그쪽에 빌려주기(노드 공유)</b>.'),
      TBL(['', '방법 (1) 사용자 초대', '방법 (2) 노드 공유 (추천)'], [
          ['친구 계정', '내 테일넷에 "사용자"로 들어옴', '친구 본인 계정 그대로 (자기 테일넷)'],
          ['무료 플랜 제한', '사용자 3명까지 (나 포함)', '사용자 수에 안 들어감 > 친구 몇 명이든 OK'],
          ['친구가 보는 것', '내 테일넷의 모든 기기', '내 서버 PC 한 대만'],
          ['내가 보는 것', '친구의 기기', '아무것도 안 보임 (정상)'],
          ['보안', '친구가 내 다른 PC/NAS에도 접근 가능', '서버 PC만 노출. 서버도 친구 쪽으로 먼저 연결 못 함(격리)'],
          ['적합한 경우', '가족·룸메이트 등 2명 이하', '그 외 전부'],
      ], [30 * mm, 68 * mm, 72 * mm]),
      P('<b>방법 (1) 사용자 초대</b>'),
      OL(['관리 콘솔 https://login.tailscale.com/admin/users > <b>Invite external users</b> > 친구 이메일 입력 > Send invite.',
          '친구는 메일의 링크로 수락 > https://tailscale.com/download 에서 앱 설치 > <b>초대받은 그 이메일</b>로 로그인.',
          '런처의 <b>연결된 기기</b> 목록에 친구 PC가 보이면 완료. 친구는 3-3의 주소로 접속.']),
      H2('노드 공유 — 처음 보는 사람을 위한 상세 절차'),
      P('<b>작동 원리:</b> 내 테일넷의 기기 목록에서 서버 PC를 골라 "공유 링크"를 만듭니다. 친구가 자기 테일스케일 계정으로 로그인한 상태에서 그 링크를 열고 Accept 하면, '
        '<b>친구의 기기 목록에 내 서버 PC가 추가</b>됩니다. 친구 입장에서는 마치 자기 테일넷에 PC가 한 대 더 생긴 것처럼 보이고, 내 입장에서는 아무 변화가 없습니다. '
        '연결은 테일스케일이 알아서 맺어 주므로 양쪽 공유기 설정은 필요 없습니다.'),
      P('<b>[내가 할 일 — 한 번만]</b>'),
      OL(['런처 네트워크 탭 <b>[관리 콘솔 열기 (기기 공유)]</b> > 브라우저에 Machines 목록이 열림.',
          '서버 PC 이름(런처의 MagicDNS 이름 앞부분, 예: <b>desktop-abc</b>) 행 오른쪽 끝 <b>···</b> 클릭 > <b>Share…</b>',
          '창에서 <b>Copy invite link</b> 탭 선택 > <b>Reusable link</b> 스위치 ON (여러 친구가 같은 링크를 쓰게) > <b>Copy share link</b>.',
          '복사한 링크를 런처 네트워크 탭의 <b>"공유 링크"</b> 칸에 붙여넣기 > 설정 저장. 이후 "친구용 안내문 복사"에 링크가 자동으로 들어갑니다.',
          '안내문을 카톡/디스코드로 보냅니다.']),
      BOX('<b>링크는 비밀번호처럼 다루세요.</b> 링크를 가진 사람은 누구나 서버 PC에 접근할 수 있습니다. 공개 채팅방에 올리지 말고, 재사용 링크는 최대 1,000회·미사용 30일 후 만료됩니다. '
          '잘못 퍼졌다면 Machines > 서버 PC > Share > ··· > <b>Revoke invite</b> 로 즉시 끊을 수 있습니다.'),
      P('<b>[친구가 할 일]</b>'),
      OL(['https://tailscale.com/download 에서 Tailscale 설치 > Google / Microsoft / GitHub / Apple 계정 아무거나로 로그인. '
          '(처음 로그인하면 친구 본인의 테일넷이 자동 생성되고, 본인이 그 테일넷의 Owner가 됩니다 — 공유 수락에 필요한 권한이 자동으로 생기는 셈)',
          '트레이의 Tailscale 아이콘이 <b>Connected</b> 인지 확인.',
          '내가 보낸 <b>공유 링크를 브라우저로 열기</b> > 로그인 상태라면 "(내 이름) wants to share desktop-abc with you" 화면 > <b>Accept</b>.',
          'Tailscale 앱 > 기기 목록(Network devices)에 <b>desktop-abc</b>가 "shared" 표시와 함께 나타나면 성공.',
          '마인크래프트 > 멀티플레이 > 서버 추가 > 주소에 안내문의 <b>Tailscale IP</b>(100.x.x.x) 입력 > 접속.']),
      P('<b>[확인 포인트]</b>'),
      UL(['공유된 서버 PC의 IP는 <b>내 테일넷에서 보이는 100.x.x.x와 보통 동일</b>합니다 (아주 드물게 친구 테일넷에서 그 IP가 이미 쓰이면 다른 100.x 주소가 배정됨 — 친구 기기 목록에 표시된 IP를 쓰면 됨).',
          'MagicDNS 이름은 <b>전체 이름</b>(desktop-abc.tail1234.ts.net)만 풀립니다. 짧은 이름(desktop-abc)은 친구 쪽에서 안 됩니다. 확실하게 하려면 IP를 알려주세요.',
          '친구 PC에서 cmd > <b>ping 100.x.x.x</b> 응답이 오면 네트워크는 된 것. 그래도 마크 접속이 안 되면 서버 PC 방화벽(6장).',
          '서버 PC에서는 친구 기기가 보이지 않고 ping도 안 됩니다. 공유는 <b>친구 > 서버 방향만</b> 열리는 격리 상태이며 마인크래프트에는 이 방향이면 충분합니다.',
          '친구가 다른 PC로 바꾸면 그 PC에도 Tailscale을 같은 계정으로 로그인하면 됩니다 — 공유는 계정(테일넷) 단위라 다시 수락할 필요 없음.',
          '친구를 내보내려면 Revoke invite(링크 전체 무효) 또는 친구가 자기 기기 목록에서 shared 기기를 Remove.']),
      H2('3-3. 친구가 입력할 서버 주소'),
      CODE('MagicDNS 이름 사용:   desktop-abc.tail1234.ts.net\nIP 사용:            100.101.102.103\n포트를 바꿨다면:      100.101.102.103:25566'),
      P('노드 공유로 들어온 친구는 MagicDNS 이름이 안 풀릴 수 있으니 <b>IP 주소</b>를 알려주는 것이 확실합니다.', 'small'),
      H2('3-4. 자주 생기는 문제'),
      TBL(['증상', '원인 / 해결'], [
          ['친구 Tailscale은 켜졌는데 접속 불가', '서버 PC 방화벽(6장) 미설정이 90%. 그다음 서버가 실제로 켜져 있는지(콘솔에 Done).'],
          ['"relay" 경유로 렉이 심함', '양쪽 공유기가 모두 엄격한 NAT일 때 DERP 릴레이를 탑니다. 한쪽이라도 공유기에서 UPnP를 켜면 대개 직접 연결로 바뀝니다. tailscale ping 100.x.x.x 로 확인.'],
          ['회사/학교 PC에서 Tailscale 설치 불가', '정책으로 막힌 환경. 포트포워딩 방식으로 전환하세요.'],
          ['로그인 URL이 안 뜸', '트레이의 Tailscale 아이콘 > Log in 으로 직접 로그인 후 런처에서 상태 새로고침.'],
          ['재부팅 후 연결 끊김', '트레이 아이콘 > Connect. 설정에서 "Run unattended"를 켜두면 로그인 전에도 자동 연결됩니다(런처 설치는 기본으로 켬).'],
      ], [60 * mm, 110 * mm]),
      PageBreak()]

# ---------------- 4 Port forwarding
F += [H1('4. 방식 B: 포트포워딩'),
      P('공유기에 "외부에서 TCP 25565로 오는 연결은 서버 PC(내부 IP)의 25565로 넘겨라"는 규칙을 추가합니다. 친구는 아무것도 설치하지 않고 내 <b>공인 IP:포트</b>로 접속합니다.'),
      H2('4-1. 준비: 런처에서 확인할 값'),
      UL(['<b>공인 IP</b> — [조회] 버튼. 예: 121.134.xx.xx (친구에게 알려줄 주소)',
          '<b>이 PC 내부 IP</b> — 예: 192.168.0.15 (공유기 규칙에 넣을 주소)',
          '<b>공유기 주소</b> — 예: 192.168.0.1 ([관리 페이지 열기]로 접속)',
          '<b>포트</b> — 설정 탭의 값. 기본 25565']),
      BOX('<b>내부 IP가 바뀌면 포트포워딩이 깨집니다.</b> 공유기 관리 페이지의 DHCP 설정에서 서버 PC의 MAC 주소에 IP를 고정(수동 할당/IP 예약)해 두세요. 대부분 "DHCP 서버 설정 > 수동 IP 할당" 메뉴에 있습니다.'),
      H2('4-2. 자동: UPnP'),
      P('공유기에 UPnP(Universal Plug and Play)가 켜져 있으면 런처가 자동으로 포트를 엽니다. 네트워크 탭에서 <b>UPnP 체크</b> > <b>[지금 UPnP 개방 시도]</b>. "V UPnP 개방됨"이 뜨면 4-3은 건너뛰어도 됩니다. 서버를 시작할 때마다 다시 열고, 종료하면 닫습니다.'),
      P('UPnP가 꺼져 있다면 공유기 관리 페이지의 "고급 설정 > UPnP" 에서 켤 수 있습니다. 보안상 UPnP를 켜기 싫다면 4-3의 수동 방식을 쓰세요.', 'small'),
      H2('4-3. 수동: 공유기 관리 페이지에서 규칙 추가'),
      P('[관리 페이지 열기] > 공유기 관리자 비밀번호로 로그인(공유기 바닥 스티커 또는 초기값). 메뉴 이름은 제조사마다 다릅니다.'),
      TBL(['제조사', '메뉴 위치', '비고'], [
          ['ipTIME', '고급 설정 > NAT/라우터 관리 > 포트포워드 설정', '규칙 이름 자유, 내부 IP, 프로토콜 TCP, 외부/내부 포트 25565~25565'],
          ['KT (GiGA WiFi 등)', '장치설정 > 트래픽 관리 > 포트 포워딩', '관리 페이지 http://172.30.1.254, 기본 ID ktuser'],
          ['SK브로드밴드', '고급설정 > NAT > 포트포워딩', '관리 페이지 http://192.168.25.1 (모델별 상이)'],
          ['LG U+', '고급설정 > NAT 설정 > 포트포워딩', '관리 페이지 http://192.168.219.1'],
          ['ASUS', 'WAN > 가상 서버/포트 포워딩', ''],
          ['TP-Link', '고급 > NAT 포워딩 > 가상 서버', ''],
          ['Netgear', '고급 > 고급 설정 > 포트 포워딩/트리거', ''],
      ], [32 * mm, 72 * mm, 66 * mm]),
      P('입력값은 공통입니다:'),
      CODE('프로토콜:        TCP  (TCP/UDP 둘 다 선택 가능하면 둘 다)\n외부(WAN) 포트:  25565\n내부(LAN) IP:    서버 PC 내부 IP (예: 192.168.0.15)\n내부(LAN) 포트:  25565'),
      H2('4-4. 확인'),
      OL(['런처에서 서버 시작 > 콘솔에 "Done" 확인.',
          '네트워크 탭 <b>[외부에서 포트 열림 확인]</b> > 사이트에서 <b>Open</b>이면 성공. Closed면 4-5 참고.',
          '친구에게 <b>공인IP:포트</b>를 알려줍니다. 포트가 25565면 IP만 알려줘도 됩니다.']),
      H2('4-5. 포트가 안 열릴 때'),
      UL(['<b>Windows 방화벽</b> 규칙 미추가 (6장) — 가장 흔함.',
          '<b>이중 NAT</b>: 통신사 모뎀도 공유기이고 그 아래에 내 공유기가 또 있는 경우. 부록 C 참고.',
          '<b>통신사 차단 / CGNAT</b>: 공인 IP 조회 결과가 100.64.x.x ~ 100.127.x.x 이거나 공유기 WAN IP와 공인 IP가 다르면 통신사가 NAT을 한 번 더 하는 것. 포트포워딩 불가 > 테일스케일로 전환.',
          '내부 IP가 바뀜 > 4-1의 IP 고정.',
          '서버가 꺼져 있음 > 확인 사이트는 실제로 응답하는 프로그램이 있어야 Open으로 나옵니다.']),
      H2('4-6. 공인 IP가 자꾸 바뀔 때 (DDNS)'),
      P('가정용 인터넷은 공인 IP가 며칠~몇 주 단위로 바뀔 수 있습니다. 공유기의 <b>DDNS</b> 기능(ipTIME: 고급 설정 > 특수 기능 > DDNS 설정)을 켜면 "내이름.iptime.org" 같은 고정 주소를 쓸 수 있습니다. 친구에게는 그 주소를 알려주세요.'),
      PageBreak()]

# ---------------- 5 LAN
F += [H1('5. 방식 C: LAN 전용'),
      P('서버 PC와 친구 PC가 같은 공유기(같은 와이파이)에 있을 때만 쓰는 방식입니다. 런처 네트워크 탭에 표시된 <b>내부 IP:포트</b>를 친구가 입력하면 끝입니다. 6장의 방화벽만 열어 주세요.'),
      UL(['공유기에 "AP 격리", "무선 클라이언트 격리", "게스트 네트워크" 가 켜져 있으면 같은 와이파이라도 서로 안 보입니다. 끄거나 일반 네트워크로 접속.',
          '마인크래프트 클라이언트의 "LAN에 공개"와는 다릅니다. TailCraft 서버는 전용 서버이므로 주소를 직접 입력해야 합니다.',
          'PC방은 PC마다 격리하는 경우가 많아 안 될 수 있습니다. 그럴 땐 테일스케일로.']),
      ]

# ---------------- 6 Firewall
F += [H1('6. Windows 방화벽 (모든 방식 공통)'),
      P('Windows는 기본적으로 외부에서 들어오는 연결을 전부 막습니다. 자바(서버)가 처음 실행될 때 "액세스 허용" 창이 뜨기도 하지만, 그 창에서 <b>공용 네트워크</b>가 체크 해제되어 있거나 창을 닫아버리면 테일스케일·LAN 접속이 모두 막힙니다.'),
      H2('6-1. 런처로 추가 (권장)'),
      P('네트워크 탭 > <b>[방화벽 허용 규칙 추가 (관리자 권한)]</b> > UAC "예". "TailCraft Minecraft" 라는 이름으로 TCP 서버 포트 인바운드 허용 규칙이 생깁니다. 상태가 "V 방화벽 허용 규칙 있음"으로 바뀌면 끝. 포트를 바꾸면 다시 눌러 주세요(기존 규칙을 덮어씁니다).'),
      H2('6-2. 직접 추가'),
      CODE('관리자 권한 PowerShell 또는 cmd:\nnetsh advfirewall firewall add rule name="Minecraft" dir=in action=allow protocol=TCP localport=25565'),
      P('또는 Windows 보안 > 방화벽 및 네트워크 보호 > 고급 설정 > 인바운드 규칙 > 새 규칙 > 포트 > TCP 25565 > 연결 허용 > 도메인/개인/공용 모두 체크.'),
      BOX('<b>백신·보안 프로그램</b>(V3, 알약, Norton 등)이 자체 방화벽을 갖고 있으면 거기서도 Java 또는 포트를 허용해야 합니다.'),
      PageBreak()]

# ---------------- 7
F += [H1('7. 친구에게 알려줄 것 / 접속 절차'),
      P('런처 대시보드의 <b>[친구용 안내문 복사]</b>를 누르면 현재 방식에 맞는 안내문이 클립보드에 복사됩니다. 카톡/디스코드에 붙여넣기만 하면 됩니다. 내용은 대략 다음과 같습니다.'),
      TBL(['방식', '친구가 할 일'], [
          ['테일스케일', '(1) Tailscale 설치·로그인(초대 수락 또는 공유 링크 Accept) (2) 마인크래프트 > 멀티플레이 > 서버 추가 > 주소에 Tailscale IP 입력'],
          ['포트포워딩', '마인크래프트 > 멀티플레이 > 서버 추가 > 공인IP(:포트) 입력'],
          ['LAN', '마인크래프트 > 멀티플레이 > 서버 추가 > 내부IP(:포트) 입력'],
      ], [32 * mm, 138 * mm]),
      P('공통: 친구의 <b>마인크래프트 버전</b>이 서버와 같아야 합니다(런처 대시보드에 표시). 모드 서버(Fabric/NeoForge/Forge, Arclight 포함)는 친구도 같은 로더 + 같은 모드를 설치해야 합니다 — 런처 모드/플러그인 탭의 <b>[친구용 모드 zip 내보내기]</b>로 묶어서 보내세요. 플러그인(EssentialsX 등)은 서버에만 있으면 되고 친구는 아무것도 설치하지 않습니다. Paper/Arclight 서버의 플러그인은 바닐라 클라이언트로도 접속 가능합니다.'),
      ]

# ---------------- 8
F += [H1('8. 문제 해결 체크리스트'),
      P('위에서부터 순서대로 확인하세요. 대부분 3번 안에서 해결됩니다.'),
      OL(['서버가 켜져 있는가? — 런처 상단 상태가 <b>실행 중</b>, 콘솔에 <b>Done (x.xxxs)!</b>',
          '내 PC에서 접속되는가? — 마인크래프트에서 <b>localhost</b>로 접속. 안 되면 네트워크 문제가 아니라 서버 문제(콘솔 오류 확인).',
          '방화벽 규칙이 있는가? — 네트워크 탭 "V 방화벽 허용 규칙 있음"',
          '(테일스케일) 양쪽 모두 Connected 인가? — 런처 "연결된 기기"에 친구가 보이는가(같은 테일넷일 때). 친구 PC에서 cmd > ping 100.x.x.x',
          '(포트포워딩) 외부 포트 확인 사이트에서 Open 인가? — Closed면 4-5',
          '(LAN) 같은 공유기인가? 격리 옵션은 꺼져 있는가?',
          '포트를 바꿨다면 친구가 주소 뒤에 :포트 를 붙였는가?',
          '버전이 같은가? "Outdated server/client" 메시지면 버전 불일치.',
          '"Failed to verify username" / "Invalid session" — online-mode가 켜져 있는데 비정품이거나 Mojang 인증 서버 장애. 정품 재로그인.',
          '접속은 되는데 렉 — 메모리 할당 증가, 시야 거리 8 이하, (테일스케일) 릴레이 경유 여부 확인.']),
      PageBreak()]

# ---------------- 9
F += [H1('9. 보안 권장 사항'),
      UL(['<b>online-mode(정품 인증)는 켜 두세요.</b> 끄면 누구나 아무 닉네임으로 들어와 관리자(OP) 닉네임을 사칭할 수 있습니다. 비정품 친구가 있다면 화이트리스트를 반드시 함께 쓰세요.',
          '<b>포트포워딩 방식은 화이트리스트 필수.</b> 공개된 포트는 몇 시간 안에 자동 스캐너에 발견됩니다. 런처 <b>플레이어 탭</b>에서 접속한 사람의 행을 고르고 [화이트리스트 추가] 한 번이면 됩니다(콘솔에서는 <b>whitelist add 닉네임</b>). 같은 탭에서 OP 부여/해제, 킥, 밴, IP 밴도 버튼으로 처리하고, 닉네임별 접속 IP·최근 접속 시각이 기록됩니다. MAC 주소는 같은 공유기(LAN) 접속자만 표시됩니다 — 인터넷/테일스케일 너머의 MAC은 어떤 서버도 알 수 없습니다.',
          'OP 권한은 꼭 필요한 사람에게만: 콘솔 <b>op 닉네임</b> / <b>deop 닉네임</b>.',
          '테일스케일은 기본적으로 테일넷 안의 기기만 접근 가능하므로 가장 안전합니다. 노드 공유 시에도 링크를 받은 사람만 들어옵니다.',
          '서버 PC의 다른 공유 서비스(파일 공유, 원격 데스크톱)는 포트포워딩하지 마세요. 마인크래프트 포트 하나만 엽니다.',
          '정기 백업: server\\world 폴더를 주기적으로 복사해 두세요.']),
      ]

# ---------------- 10 부록
F += [H1('10. 부록'),
      H2('A. 포트 바꾸기'),
      P('설정 탭에서 포트를 바꾸고 저장 > 네트워크 탭에서 방화벽 규칙 다시 추가 > (포트포워딩) 공유기 규칙도 새 포트로 수정 > 친구에게 <b>주소:새포트</b> 형식으로 알려주기.'),
      H2('B. 공인 IP가 바뀌었을 때 (포트포워딩)'),
      P('네트워크 탭 [조회]로 새 IP 확인 후 친구에게 다시 알려주면 됩니다. 공유기 규칙은 내부 IP 기준이라 손댈 필요 없습니다. 자주 바뀌면 4-6의 DDNS.'),
      H2('C. 이중 NAT (공유기 두 대)'),
      P('통신사 모뎀/공유기 아래에 내 공유기를 또 연결한 구조입니다. 인터넷 > 모뎀(공유기1) > 내 공유기(공유기2) > PC. 이 경우 포트포워딩을 <b>두 번</b> 해야 합니다.'),
      OL(['공유기2(내 공유기) 관리 페이지에서 WAN IP를 확인 (예: 192.168.1.5). 이 값이 사설 IP(192.168.x.x / 10.x.x.x / 172.16~31.x.x)면 이중 NAT.',
          '공유기1(모뎀) 관리 페이지에서 25565 > 공유기2의 WAN IP(192.168.1.5)로 포트포워딩.',
          '공유기2에서 25565 > 서버 PC 내부 IP로 포트포워딩(4-3).',
          '더 간단한 방법: 공유기2를 "브리지/AP 모드"로 바꾸거나, 그냥 테일스케일을 쓰세요.']),
      H2('D. 테일스케일 용어'),
      TBL(['용어', '뜻'], [
          ['테일넷(Tailnet)', '내 계정에 묶인 기기들의 사설망. 가입하면 자동 생성.'],
          ['MagicDNS', '기기 이름으로 접속하게 해 주는 내부 DNS. 예: desktop-abc.tail1234.ts.net'],
          ['노드 공유(Node sharing)', '내 테일넷의 기기 하나를 다른 테일넷 사용자에게 공유 링크로 빌려줌. 받는 쪽 기기 목록에 그 기기가 추가되고 보통 같은 100.x IP로 접속. 사용자 수 제한에 안 걸림. 3-2 참고.'],
          ['DERP 릴레이', '직접 연결이 불가능할 때 경유하는 테일스케일 중계 서버. 느려지는 원인.'],
          ['Funnel', '테일스케일 없이도 인터넷에서 접속하게 공개하는 기능. TCP 지원하지만 릴레이 경유라 게임엔 비추.'],
      ], [45 * mm, 125 * mm]),
      Spacer(1, 10 * mm),
      P('문서 끝. 런처의 도움말 탭에서 튜토리얼을 다시 볼 수 있습니다.', 'small')]

doc.build(F, onFirstPage=footer, onLaterPages=footer)
print('ok', OUT)
