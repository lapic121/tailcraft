# -*- coding: utf-8 -*-
"""TailCraft Network Setup Guide (English) — same layout as the Korean guide."""
import sys, os
sys.argv = [sys.argv[0], sys.argv[1]]
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'pdf_common.py'), encoding='utf-8').read())

def footer(c, d):
    c.saveState(); c.setFont('KR', 8.5); c.setFillColor(MUT)
    c.drawString(20 * mm, 12 * mm, 'TailCraft Network Setup Guide')
    c.drawRightString(A4[0] - 20 * mm, 12 * mm, f'{d.page}')
    c.restoreState()

doc = SimpleDocTemplate(OUT, pagesize=A4, leftMargin=20 * mm, rightMargin=20 * mm, topMargin=18 * mm, bottomMargin=20 * mm,
                        title='TailCraft Network Setup Guide', author='TailCraft')
F = []

F += [Spacer(1, 50 * mm), P('TailCraft', 'title'), P('Minecraft Server Network Setup Guide', 'sub'), Spacer(1, 6 * mm),
      P('Tailscale | Port forwarding | LAN — every way to let friends join your server', 'sub'), Spacer(1, 60 * mm),
      P('Read this alongside the "Network" tab of the launcher. Chapter numbers match the launcher tutorial steps.', 'small'), PageBreak()]

F += [H1('Contents'), OL([
    'Why network setup is needed (routers and NAT)',
    'The three methods compared',
    'Method A: Tailscale (recommended)',
    'Method B: Port forwarding',
    'Method C: LAN only',
    'Windows Firewall (all methods)',
    'What to tell your friends / how they join',
    'Troubleshooting checklist',
    'Security recommendations',
    'Appendix: changing the port, public IP changes, double NAT, Tailscale glossary',
]), PageBreak()]

F += [H1('1. Why network setup is needed'),
      P('Your home <b>router</b> gets <b>one public IP</b> from your ISP and shares it with every device in the house, giving each device a <b>private IP</b> such as 192.168.x.x. This is called NAT.'),
      P('The problem is <b>incoming</b> connections. When a friend connects to your public IP, the router has no idea which PC inside the house should receive it, so it drops the packet. To host a Minecraft server you must do one of these:'),
      UL(['Tell the router "send everything on port 25565 to this PC" > <b>Port forwarding</b>',
          'Bypass the router with a private VPN that links you and your friends directly > <b>Tailscale</b>',
          'Skip the internet entirely and only play on the same router > <b>LAN</b>']),
      P('Whichever you choose, <b>Windows Firewall</b> must allow the server port at the end (chapter 6). Forgetting this is the #1 cause of "my friend can\'t connect".')]

F += [H1('2. The three methods compared'),
      TBL(['', 'Tailscale', 'Port forwarding', 'LAN'], [
          ['Router setup', 'None', 'Required (automatic with UPnP)', 'None'],
          ['What friends do', 'Install Tailscale + log in', 'Nothing (just type the address)', 'Nothing'],
          ['Security', 'Encrypted P2P, no port exposed to the internet', 'Port is public > scanners and random joins', 'Not reachable from outside'],
          ['Latency', 'Usually direct (P2P); some networks fall back to a relay', 'Direct, fastest', 'Fastest'],
          ['Player limit', 'Free plan: 3 users / 100 devices — node sharing bypasses the user limit', 'None', 'None'],
          ['Public IP changes', 'Irrelevant', 'You must tell friends the new IP (or use DDNS)', 'Irrelevant'],
          ['Dorm / office / mobile data (can\'t open ports)', 'Works', 'Does not work', '-'],
      ], [28 * mm, 48 * mm, 52 * mm, 42 * mm]),
      BOX('<b>Recommendation:</b> up to ~10 friends and you don\'t want to touch the router > <b>Tailscale</b>. Open to strangers, or friends refuse to install anything > <b>Port forwarding</b>. Same Wi-Fi at home or a LAN cafe > <b>LAN</b>.'),
      PageBreak()]

F += [H1('3. Method A: Tailscale (recommended)'),
      P('Tailscale is a personal VPN built on WireGuard. Install the app on your PC and on your friends\' PCs, put them in the same "tailnet", and they can talk to each other directly over fixed 100.x.x.x addresses. It does not matter what router or ISP anyone has, and all traffic is end-to-end encrypted.'),
      H2('3-1. Server PC setup (launcher > Network tab)'),
      OL(['Click <b>[1. Install Tailscale]</b> > answer "Yes" to the User Account Control prompt. The install is silent and takes about a minute.',
          'Click <b>[2. Log in / Connect]</b> > a browser opens; sign in with Google / Microsoft / GitHub / Apple. The first sign-in creates your tailnet automatically.',
          'Back in the launcher click <b>[Refresh status]</b>. The state becomes <b>Connected</b> and the <b>Tailscale IP</b> (100.x.x.x) and <b>MagicDNS name</b> (e.g. desktop-abc.tail1234.ts.net) are filled in.',
          'Add the firewall rule from chapter 6.']),
      H2('3-2. Inviting friends — two ways'),
      P('Tailscale only lets devices <b>in the same tailnet (account)</b> talk to each other, so there are exactly two ways to let a friend in: '
        '<b>(1) invite the friend as a user of your tailnet</b>, or <b>(2) let the friend use their own tailnet and lend them just your server PC (node sharing)</b>.'),
      TBL(['', '(1) Invite user', '(2) Node sharing (recommended)'], [
          ['Friend\'s account', 'Becomes a user of <i>your</i> tailnet', 'Their own account, their own tailnet'],
          ['Free plan limit', '3 users including you', 'Not counted as users > any number of friends'],
          ['What the friend sees', 'Every device in your tailnet', 'Only your server PC'],
          ['What you see', 'The friend\'s devices', 'Nothing (this is normal)'],
          ['Security', 'Friend can reach your other PCs / NAS', 'Only the server is exposed; the server cannot initiate connections to the friend (quarantined)'],
          ['Best for', 'Family / roommates, 2 people max', 'Everything else'],
      ], [30 * mm, 68 * mm, 72 * mm]),
      P('<b>(1) Invite user</b>'),
      OL(['Admin console https://login.tailscale.com/admin/users > <b>Invite external users</b> > enter the friend\'s e-mail > Send invite.',
          'Friend accepts from the e-mail link > installs from https://tailscale.com/download > signs in with <b>that same e-mail</b>.',
          'When the friend\'s PC shows up in the launcher\'s <b>Connected devices</b> list, you are done. They connect with the address in 3-3.']),
      H2('Node sharing — step by step for first-timers'),
      P('<b>How it works:</b> in your tailnet\'s machine list you pick the server PC and create a "share link". When a friend, signed in to <i>their own</i> Tailscale account, opens that link and clicks Accept, '
        '<b>your server PC is added to the friend\'s device list</b>. From the friend\'s point of view it looks like one extra PC appeared in their tailnet; from your side nothing changes. '
        'Tailscale sets up the connection itself, so neither router needs any configuration.'),
      P('<b>[What you do — once]</b>'),
      OL(['Launcher > Network tab > <b>[Open admin console (share device)]</b> > the Machines list opens in your browser.',
          'Find the row for your server PC (the first part of the MagicDNS name, e.g. <b>desktop-abc</b>) > click <b>...</b> at the right end > <b>Share...</b>',
          'Choose the <b>Copy invite link</b> tab > turn on <b>Reusable link</b> (so several friends can use the same link) > <b>Copy share link</b>.',
          'Paste the link into the <b>"Share link"</b> box in the launcher\'s Network tab > Save settings. From now on "Copy invite for friends" includes the link automatically.',
          'Send the invite text over Discord / chat.']),
      BOX('<b>Treat the link like a password.</b> Anyone holding it can reach your server PC. Never post it in a public channel. A reusable link works up to 1,000 times and expires after 30 days unused. '
          'If it leaks: Machines > server PC > Share > ... > <b>Revoke invite</b> cuts everyone off immediately.'),
      P('<b>[What the friend does]</b>'),
      OL(['Install Tailscale from https://tailscale.com/download > sign in with any Google / Microsoft / GitHub / Apple account. '
          '(The first sign-in creates the friend\'s own tailnet with them as Owner — which is exactly the permission needed to accept a share.)',
          'Check that the Tailscale tray icon says <b>Connected</b>.',
          'Open the share link you sent <b>in a browser</b> > while signed in, a page says "(your name) wants to share desktop-abc with you" > <b>Accept</b>.',
          'In the Tailscale app > device list, <b>desktop-abc</b> now appears marked "shared". Success.',
          'Minecraft > Multiplayer > Add Server > address = the <b>Tailscale IP</b> (100.x.x.x) from the invite text > Join.']),
      P('<b>[Things to check]</b>'),
      UL(['The shared server keeps <b>the same 100.x.x.x IP</b> you see in your own tailnet (very rarely, if that IP is already used in the friend\'s tailnet, a different 100.x address is assigned — use whatever IP their device list shows).',
          'MagicDNS resolves only the <b>full name</b> (desktop-abc.tail1234.ts.net) from the friend\'s side; the short name (desktop-abc) does not. Giving the IP is the safest.',
          'On the friend\'s PC: cmd > <b>ping 100.x.x.x</b>. A reply means the network is fine; if Minecraft still fails, it is the server\'s Windows Firewall (chapter 6).',
          'From the server PC you cannot see or ping the friend\'s devices. A share is one-way (<b>friend > server</b>) by design, and that is all Minecraft needs.',
          'If the friend switches PCs they just sign in to Tailscale on the new PC with the same account — the share belongs to the account, no need to accept again.',
          'To kick a friend: Revoke invite (kills the whole link) or the friend removes the shared device from their own list.']),
      H2('3-3. Address the friend types'),
      CODE('MagicDNS name:        desktop-abc.tail1234.ts.net\nIP address:           100.101.102.103\nNon-default port:     100.101.102.103:25566'),
      P('Friends who joined via node sharing may not resolve the MagicDNS name — give them the <b>IP</b>.', 'small'),
      H2('3-4. Common problems'),
      TBL(['Symptom', 'Cause / fix'], [
          ['Friend\'s Tailscale is Connected but can\'t join', '90% of the time: server firewall (chapter 6). Then: is the server actually running (console shows Done)?'],
          ['Heavy lag, connection goes through a "relay"', 'Both routers have strict NAT so traffic uses a DERP relay. Enabling UPnP on either router usually restores a direct connection. Check with: tailscale ping 100.x.x.x'],
          ['Cannot install Tailscale on a work/school PC', 'Blocked by policy. Switch to port forwarding.'],
          ['No login URL appears', 'Tray icon > Log in manually, then Refresh status in the launcher.'],
          ['Disconnected after reboot', 'Tray icon > Connect. The launcher installs with "Run unattended" so it normally reconnects before login.'],
      ], [60 * mm, 110 * mm]),
      PageBreak()]

F += [H1('4. Method B: Port forwarding'),
      P('You add a rule to the router: "TCP 25565 arriving from the internet goes to the server PC (private IP), port 25565". Friends install nothing and connect to your <b>public IP:port</b>.'),
      H2('4-1. Values shown in the launcher'),
      UL(['<b>Public IP</b> — [Look up] button, e.g. 121.134.xx.xx (what friends type)',
          '<b>This PC\'s local IP</b> — e.g. 192.168.0.15 (goes into the router rule)',
          '<b>Router address</b> — e.g. 192.168.0.1 ([Open admin page])',
          '<b>Port</b> — from the Settings tab, default 25565']),
      BOX('<b>If the local IP changes, the rule breaks.</b> In the router\'s DHCP settings reserve a fixed IP for the server PC\'s MAC address ("DHCP reservation" / "static lease").'),
      H2('4-2. Automatic: UPnP'),
      P('If the router has UPnP enabled, the launcher opens the port by itself: Network tab > tick <b>UPnP</b> > <b>[Try UPnP now]</b>. If it shows "UPnP opened" you can skip 4-3. The port is re-opened at every server start and closed on stop.'),
      P('UPnP can usually be enabled under the router\'s Advanced > UPnP page. If you prefer not to enable UPnP, use the manual method below.', 'small'),
      H2('4-3. Manual: add the rule in the router admin page'),
      P('[Open admin page] > log in with the router password (sticker on the router or the default). Menu names differ by vendor:'),
      TBL(['Vendor', 'Menu', 'Notes'], [
          ['ASUS', 'WAN > Virtual Server / Port Forwarding', ''],
          ['TP-Link', 'Advanced > NAT Forwarding > Virtual Servers', ''],
          ['Netgear', 'Advanced > Advanced Setup > Port Forwarding / Port Triggering', ''],
          ['Linksys', 'Security > Apps and Gaming > Single Port Forwarding', ''],
          ['Ubiquiti / UniFi', 'Settings > Firewall & Security > Port Forwarding', ''],
          ['ISP-provided gateways', 'Usually under Advanced / NAT / Port Forwarding', 'Admin page address is printed on the device'],
      ], [32 * mm, 72 * mm, 66 * mm]),
      P('The values are the same everywhere:'),
      CODE('Protocol:            TCP  (TCP+UDP if that is the only option)\nExternal (WAN) port: 25565\nInternal (LAN) IP:   server PC local IP (e.g. 192.168.0.15)\nInternal (LAN) port: 25565'),
      H2('4-4. Verify'),
      OL(['Start the server in the launcher > console shows "Done".',
          'Network tab > <b>[Check port from outside]</b> > the site must say <b>Open</b>. If Closed, see 4-5.',
          'Tell friends <b>publicIP:port</b> (just the IP if the port is 25565).']),
      H2('4-5. Port stays closed'),
      UL(['<b>Windows Firewall</b> rule missing (chapter 6) — most common.',
          '<b>Double NAT</b>: the ISP modem is also a router and your own router sits behind it. See appendix C.',
          '<b>CGNAT / ISP blocking</b>: if the public IP lookup shows 100.64.x.x – 100.127.x.x, or the router\'s WAN IP differs from the public IP, the ISP is doing NAT too. Port forwarding is impossible > use Tailscale.',
          'Local IP changed > reserve it (4-1).',
          'Server not running > the checker only reports Open when something answers.']),
      H2('4-6. Public IP keeps changing (DDNS)'),
      P('Home connections change public IP every few days or weeks. Enable <b>DDNS</b> on the router (most vendors support No-IP, DynDNS or their own service) to get a fixed name like myserver.ddns.net and give friends that name instead.'),
      PageBreak()]

F += [H1('5. Method C: LAN only'),
      P('Only for when the server PC and friends are on the same router (same Wi-Fi). Friends type the <b>local IP:port</b> shown in the launcher\'s Network tab. Just add the firewall rule (chapter 6).'),
      UL(['If the router has "AP isolation", "wireless client isolation" or a guest network enabled, devices cannot see each other even on the same Wi-Fi. Disable it or use the main network.',
          'This is not the same as Minecraft\'s "Open to LAN". TailCraft runs a dedicated server, so friends must type the address.',
          'Internet cafes often isolate every PC; use Tailscale there.'])]

F += [H1('6. Windows Firewall (all methods)'),
      P('Windows blocks all incoming connections by default. Java may pop up an "Allow access" dialog on first run, but if <b>Public networks</b> is unticked there, or the dialog is closed, Tailscale and LAN connections are blocked.'),
      H2('6-1. Via the launcher (recommended)'),
      P('Network tab > <b>[Add firewall allow rule (admin)]</b> > UAC "Yes". A rule named "TailCraft Minecraft" allowing inbound TCP on the server port is created and the status changes to "Firewall rule present". If you change the port, click it again (the rule is replaced).'),
      H2('6-2. Manually'),
      CODE('Administrator PowerShell or cmd:\nnetsh advfirewall firewall add rule name="Minecraft" dir=in action=allow protocol=TCP localport=25565'),
      P('Or: Windows Security > Firewall & network protection > Advanced settings > Inbound Rules > New Rule > Port > TCP 25565 > Allow > tick Domain, Private and Public.'),
      BOX('<b>Third-party antivirus suites</b> (Norton, McAfee, Kaspersky, etc.) often have their own firewall — allow Java or the port there as well.'),
      PageBreak()]

F += [H1('7. What to tell your friends / how they join'),
      P('Dashboard > <b>[Copy invite for friends]</b> puts a ready-made message for the current method on the clipboard. Paste it into Discord or chat. It covers roughly this:'),
      TBL(['Method', 'What the friend does'], [
          ['Tailscale', '(1) Install Tailscale, sign in, accept the invite or open the share link > Accept (2) Minecraft > Multiplayer > Add Server > Tailscale IP'],
          ['Port forwarding', 'Minecraft > Multiplayer > Add Server > publicIP(:port)'],
          ['LAN', 'Minecraft > Multiplayer > Add Server > localIP(:port)'],
      ], [32 * mm, 138 * mm]),
      P('Always: the friend\'s <b>Minecraft version</b> must match the server (shown on the dashboard). Modded servers (Fabric / NeoForge / Forge, including Arclight) require friends to install the same loader and the same mods — use <b>[Export mods zip for friends]</b> in the launcher\'s Mods/Plugins tab. Plugins (EssentialsX etc.) live only on the server; friends install nothing. Paper/Arclight servers accept vanilla clients.')]

F += [H1('8. Troubleshooting checklist'),
      P('Go top to bottom. Most cases are solved by step 3.'),
      OL(['Is the server running? Launcher header says <b>Running</b>, console shows <b>Done (x.xxxs)!</b>',
          'Can you join from the server PC itself? Minecraft > address <b>localhost</b>. If not, it is a server problem, not network (check the console).',
          'Firewall rule present? Network tab shows "Firewall rule present".',
          '(Tailscale) Both sides Connected? Friend appears in "Connected devices" (same tailnet) or shared device shows in friend\'s list. From friend\'s PC: ping 100.x.x.x',
          '(Port forwarding) External port checker says Open? If Closed, 4-5.',
          '(LAN) Same router? Isolation disabled?',
          'Non-default port: did the friend add :port to the address?',
          'Same version? "Outdated server/client" means a version mismatch.',
          '"Failed to verify username" / "Invalid session": online-mode is on and the friend is not using a licensed account, or Mojang auth is down. Re-login.',
          'Joins but lags: raise memory, view distance 8 or lower, (Tailscale) check for relay.']),
      PageBreak()]

F += [H1('9. Security recommendations'),
      UL(['<b>Keep online-mode (license check) on.</b> With it off, anyone can join under any name — including an admin\'s name. If you must support unlicensed friends, always combine it with a whitelist.',
          '<b>Port forwarding requires a whitelist.</b> A public port is found by automated scanners within hours. In the launcher\'s <b>Players tab</b> select the row of someone who joined and click [Add to whitelist] (console equivalent: <b>whitelist add name</b>). The same tab offers OP / de-OP, kick, ban and IP-ban buttons and records each nickname\'s IP and last login. MAC addresses are shown only for players on the same router (LAN) — no server can see the MAC of someone connecting over the internet or Tailscale.',
          'Give OP only to people who need it: console <b>op name</b> / <b>deop name</b>.',
          'Tailscale is the safest by default: only devices in the tailnet (or holders of a share link) can reach the server.',
          'Never port-forward other services (file sharing, Remote Desktop). Open the Minecraft port only.',
          'Back up server\\world regularly.'])]

F += [H1('10. Appendix'),
      H2('A. Changing the port'),
      P('Settings tab > change the port > Save > Network tab > add the firewall rule again > (port forwarding) update the router rule > tell friends <b>address:newport</b>.'),
      H2('B. Public IP changed (port forwarding)'),
      P('Network tab > [Look up] > send friends the new IP. The router rule uses the local IP, so it needs no change. If it changes often, use DDNS (4-6).'),
      H2('C. Double NAT (two routers)'),
      P('Internet > ISP modem/router (router 1) > your router (router 2) > PC. You must forward the port <b>twice</b>.'),
      OL(['In router 2\'s admin page, read its WAN IP (e.g. 192.168.1.5). If it is a private address (192.168.x.x / 10.x.x.x / 172.16-31.x.x) you have double NAT.',
          'In router 1, forward 25565 to router 2\'s WAN IP (192.168.1.5).',
          'In router 2, forward 25565 to the server PC\'s local IP (4-3).',
          'Simpler: put router 2 in bridge/AP mode, or just use Tailscale.']),
      H2('D. Tailscale glossary'),
      TBL(['Term', 'Meaning'], [
          ['Tailnet', 'The private network of devices tied to your account. Created automatically on first sign-in.'],
          ['MagicDNS', 'Internal DNS that lets you use device names, e.g. desktop-abc.tail1234.ts.net'],
          ['Node sharing', 'Lending one device of your tailnet to users of other tailnets via a share link. The device appears in their list, usually with the same 100.x IP. Does not consume user seats. See 3-2.'],
          ['DERP relay', 'Tailscale relay servers used when a direct connection is impossible. The cause of extra latency.'],
          ['Funnel', 'Exposes a service to the public internet without Tailscale on the client. Supports TCP but always relayed — not recommended for games.'],
      ], [45 * mm, 125 * mm]),
      Spacer(1, 10 * mm),
      P('End of document. The tutorial can be replayed from the launcher\'s Help tab.', 'small')]

doc.build(F, onFirstPage=footer, onLaterPages=footer)
print('ok', OUT)
