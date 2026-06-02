import socket
import struct

HOST = "2003:102:ef1b:fb77:68ed:301:6fd:397"  
PORT = 5000
HEADER_FORMAT = "!Q I"
HEADER_SIZE = struct.calcsize(HEADER_FORMAT)

server_sock = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
server_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

try:
    server_sock.bind((HOST, PORT, 0, 0))
    server_sock.listen(1)
    print(f"Datei-Server bereit auf Port {PORT}...")
except Exception as e:
    print(f"Fehler beim Start: {e}")
    exit(1)

try:
    conn, addr = server_sock.accept()
    print(f"[+] Client verbunden: {addr}")

    with conn:
        # 1. Header empfangen
        header_data = conn.recv(HEADER_SIZE)
        if not header_data:
            print("[-] Keine Header-Daten empfangen.")
            exit()

        # Header entpacken: Dateigröße und Länge des Dateinamens
        file_size, name_length = struct.unpack(HEADER_FORMAT, header_data)

        # 2. Dateinamen empfangen
        filename = conn.recv(name_length).decode('utf-8')
        print(f"[+] Empfange Datei: '{filename}' ({file_size} Bytes)")

        # 3. Dateiinhalt blockweise empfangen und direkt speichern
        output_filename = f"received_{filename}"
        bytes_received = 0
        
        with open(output_filename, "wb") as f:
            while bytes_received < file_size:
                # Berechne, wie viel noch übrig ist, um nicht zu viel zu lesen
                remaining = file_size - bytes_received
                chunk_size = min(4096, remaining) 
                
                data = conn.recv(chunk_size)
                if not data:
                    raise ConnectionAbortedError("Verbindung mitten im Download abgebrochen!")
                
                f.write(data)
                bytes_received += len(data)
                
                # Fortschritt anzeigen
                print(f"\rFortschritt: {bytes_received / file_size * 100:.2f}%", end="")

        print(f"\n[+] Datei erfolgreich gespeichert unter: {output_filename}")

except Exception as e:
    print(f"\n[-] Fehler beim Datentransfer: {e}")
finally:
    server_sock.close()