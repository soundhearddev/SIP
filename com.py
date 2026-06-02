import socket
import sys

HOST = "2003:102:ef1b:fb77:68ed:301:6fd:397"  
PORT = 5005

# Erstellt den IPv6 TCP Socket
# SO_REUSEADDR sorgt dafür, dass der Port nach einem Neustart sofort wieder frei ist
server_sock = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
server_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

try:
    server_sock.bind((HOST, PORT, 0, 0))
    server_sock.listen(5) # Erlaube eine kleine Warteschlange
    print(f"Server läuft auf [{HOST}]:{PORT} und wartet auf Verbindungen...")
except Exception as e:
    print(f"Fehler beim Starten des Servers: {e}")
    sys.exit(1)

try:
    while True:
        try:
            conn, addr = server_sock.accept()
            print(f"\n[+] Client verbunden: {addr}")
        except KeyboardInterrupt:
            print("\n[-] Server wird durch Benutzer beendet.")
            break
        except Exception as e:
            print(f"Fehler bei Verbindungsannahme: {e}")
            continue

        # 'with' garantiert, dass die Verbindung am Ende IMMER geschlossen wird
        with conn:
            buffer = ""
            while True:
                try:
                    # Aufforderung senden (wichtig: mit \n als Trennzeichen!)
                    conn.sendall(b"DEIN ZUG:\n")

                    # Daten empfangen
                    data = conn.recv(4096)
                    if not data:
                        print("[-] Client hat die Verbindung sauber geschlossen.")
                        break

                    # Nachricht decodieren (Fehler abfangen, falls Müll geschickt wird)
                    buffer += data.decode('utf-8', errors='ignore')
                    
                    # Verarbeite Zeile für Zeile (TCP-Streaming-Schutz)
                    while "\n" in buffer:
                        msg, buffer = buffer.split("\n", 1)
                        msg = msg.strip()
                        
                        print(f"Client sagt: {msg}")

                        if msg.upper() == "STOP":
                            conn.sendall(b"Server beendet\n")
                            print("[-] STOP-Signal erhalten. Schließe Verbindung.")
                            break

                        # Server-Antwort eingeben
                        try:
                            reply = input("Server > ").strip()
                        except (KeyboardInterrupt, EOFError):
                            reply = "STOP"
                        
                        conn.sendall((reply + "\n").encode('utf-8'))
                        
                        if reply.upper() == "STOP":
                            break
                    
                    if "STOP" in msg.upper() or ( 'reply' in locals() and reply.upper() == "STOP" ):
                        break

                except ConnectionResetError:
                    print("[-] Verbindung vom Client unerwartet abgebrochen (Reset).")
                    break
                except Exception as e:
                    print(f"[-] Fehler während der Kommunikation: {e}")
                    break
                    
finally:
    server_sock.close()
    print("[----] Server-Socket geschlossen.")