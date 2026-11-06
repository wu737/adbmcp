import socket, concurrent.futures, sys, subprocess, time

PORTS = [5555, 5554, 5037, 37099, 39000]
NET = sys.argv[1] if len(sys.argv) > 1 else "192.168.110"

def probe(args):
    last, port = args
    ip = f"{NET}.{last}"
    s = socket.socket()
    s.settimeout(0.4)
    try:
        s.connect((ip, port))
        s.close()
        return (ip, port)
    except Exception:
        return None

tasks = [(i, p) for i in range(1, 255) for p in PORTS]
hits = []
with concurrent.futures.ThreadPoolExecutor(128) as ex:
    for r in ex.map(probe, tasks):
        if r:
            hits.append(r)

print(f"=== {NET}.0/24 scan result ===")
for ip, port in sorted(hits):
    print(f"  {ip}:{port}")

if hits:
    print("=== try adb connect ===")
    for ip, port in sorted(hits):
        if port in (5555, 5554):
            out = subprocess.run(["adb", "connect", f"{ip}:{port}"],
                                 capture_output=True, text=True, timeout=20)
            print(f"  {ip}:{port} -> {out.stdout.strip()}{out.stderr.strip()}")
            time.sleep(1.5)
print("=== adb devices ===")
print(subprocess.run(["adb", "devices"], capture_output=True, text=True).stdout)
