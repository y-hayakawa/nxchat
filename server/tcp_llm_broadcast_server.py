#!/usr/bin/env python3
import asyncio
import os
import openai
import sqlite3
import signal
import sys
import datetime
import shutil
from sqlite3 import Connection

# Filename: tcp_llm_broadcast_server.py
# Persistent multi-client LLM broadcast server using SQLite

# Load OpenAI API key from environment
openai.api_key = os.getenv("OPENAI_API_KEY")

# Configuration
HOST = '0.0.0.0'
PORT = 12345
DB_PATH = 'chat_history.db'
ALLOWED_IPS = {
    '127.0.0.1',  # Localhost
    '192.168.1.2',
}
MAX_PROMPT_LENGTH = 2000  # Adjust as needed

# Global state
clients = set()
conversation_history = []
db_conn: Connection = None  

def init_db(path: str) -> Connection:
    conn = sqlite3.connect(path)
    cur = conn.cursor()
    cur.execute(
        '''
        CREATE TABLE IF NOT EXISTS messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
        )
        '''
    )
    conn.commit()
    # Load history
    cur.execute('SELECT role, content FROM messages ORDER BY id')
    rows = cur.fetchall()
    if rows:
        for role, content in rows:
            conversation_history.append({"role": role, "content": content})
    else:
        system_prompt = {"role": "system", "content": "You are a helpful assistant in a multi-client group chat."}
        conversation_history.append(system_prompt)
        cur.execute(
            'INSERT INTO messages (role, content) VALUES (?, ?)',
            (system_prompt['role'], system_prompt['content'])
        )
        conn.commit()
    return conn

def backup_database(path: str) -> str:
    """
    現在のデータベースファイルを YYYYMMDD-HHMMSS.bak.sqlite のような
    タイムスタンプ付きファイル名でコピーし、そのパスを返す。
    """
    timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_path = f"{path}.{timestamp}.bak"
    shutil.copy(path, backup_path)
    return backup_path

def save_message(conn: Connection, role: str, content: str):
    cur = conn.cursor()
    cur.execute(
        'INSERT INTO messages (role, content) VALUES (?, ?)',
        (role, content)
    )
    conn.commit()

async def broadcast(message: str):
    disconnected = []
    for writer in clients:
        try:
            writer.write(message.encode() + b"\n\0")
            await writer.drain()
        except Exception:
            disconnected.append(writer)
    for writer in disconnected:
        clients.discard(writer)

async def handle_client(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, db_conn: Connection):
    peer = writer.get_extra_info('peername')
    ip = peer[0]
    print(f"Connection from {ip}")

    if ip not in ALLOWED_IPS:
        print(f"IP {ip} not allowed. Closing connection.")
        writer.close()
        await writer.wait_closed()
        return

    clients.add(writer)
    buffer = b""
    try:
        while True:
            chunk = await reader.read(1024)
            if not chunk:
                break
            buffer += chunk

            while True:
                idx = buffer.find(b'\0')
                if idx == -1:
                    break
                raw = buffer[:idx]
                buffer = buffer[idx+1:]

                text = raw.decode(errors='ignore')
                print(f"Received from {ip}: {text}")

                # Recall command handling
                if text.startswith("/recall"):
                    parts = text.split()
                    # Determine range
                    if len(parts) == 1:
                        # recall last interaction (user + assistant)
                        items = conversation_history[-2:]
                    elif parts[1] == 'all':
                        items = conversation_history
                    else:
                        try:
                            n = int(parts[1])
                            items = conversation_history[-n*2:] if n>0 else []
                        except ValueError:
                            items = []
                    # Send recalled history
                    for msg in items:
                        if msg['role'] == 'user':
                            writer.write(f"[User]\n{msg['content']}".encode() + b"\n\0")
                        elif msg['role'] == 'assistant':
                            writer.write(f"[ChatGPT]\n{msg['content']}".encode() + b"\n\n\0")
                    await writer.drain()
                    continue

                # Enforce prompt length limit
                if len(text) > MAX_PROMPT_LENGTH:
                    warning = f"[SERVER] Prompt too long ({len(text)} chars). Limit is {MAX_PROMPT_LENGTH}."
                    writer.write(warning.encode() + b"\n\0")
                    await writer.drain()
                    continue

                # Command: reset system prompt
                if text.startswith("/system "):
                    new_prompt = text[len("/system "):]
                    conversation_history.clear()
                    conversation_history.append({"role": "system", "content": new_prompt})
                    save_message(db_conn, "system", new_prompt)
                    await broadcast(f"[SERVER] System prompt updated to: {new_prompt}")
                    continue

                if text == "/reset":
                    # 1) DB バックアップ
                    backup_path = backup_database(DB_PATH)
                    # 2) インメモリ履歴クリア
                    conversation_history.clear()
                    # 3) SQLite テーブルを完全削除して再作成
                    cur = db_conn.cursor()
                    cur.execute("DROP TABLE IF EXISTS messages")
                    cur.execute("""
                    CREATE TABLE messages (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    role TEXT NOT NULL,
                    content TEXT NOT NULL,
                    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
                    )
                    """)
                    db_conn.commit()
                    # 4) デフォルトの system プロンプトを再挿入
                    system_prompt = {"role": "system", "content": "You are a helpful assistant in a multi-client group chat."}
                    conversation_history.append(system_prompt)
                    cur.execute(
                        "INSERT INTO messages (role, content) VALUES (?, ?)",
                        (system_prompt["role"], system_prompt["content"])
                    )
                    db_conn.commit()
                    # 5) クライアントへの通知
                    await broadcast(f"[SERVER] Conversation history reset. Database backed up to {backup_path}")
                    continue

                # Append user message
                conversation_history.append({"role": "user", "content": text})
                save_message(db_conn, "user", text)

                # Call OpenAI API
                response = openai.chat.completions.create(
                    model="gpt-4o-mini",
                    messages=conversation_history
                )
                ai_message = response.choices[0].message.content.strip()
                print(f"AI: {ai_message}")

                conversation_history.append({"role": "assistant", "content": ai_message})
                save_message(db_conn, "assistant", ai_message)

                # Broadcast user + AI
                await broadcast(f"[{ip}]\n{text}\n")
                await broadcast(f"[ChatGPT]\n{ai_message}\n\n")
    except Exception as e:
        print(f"Error with {ip}: {e}")
        warning = f"[SERVER] `{e}`"        
        writer.write(warning.encode() + b"\n\0")
        await writer.drain()
    finally:
        print(f"Disconnecting {ip}")
        clients.discard(writer)
        writer.close()
        await writer.wait_closed()

async def main():
    global db_conn
    db_conn = init_db(DB_PATH) 
    server = await asyncio.start_server(
        lambda r, w: handle_client(r, w, db_conn),
        HOST, PORT
    )
    addr = server.sockets[0].getsockname()
    print(f"Serving on {addr}")

    async with server:
        await server.serve_forever()

def _shutdown(signum, frame):
    """SIGINT/SIGTERM で呼ばれるハンドラ"""
    print("\nShutdown signal received, saving database…")
    if db_conn:
        db_conn.commit()
        db_conn.close()
        print("Database committed and closed.")
    # クライアントソケットも閉じておく
    for w in list(clients):
        w.close()
    sys.exit(0)

if __name__ == '__main__':
    # シグナルハンドラ登録
    signal.signal(signal.SIGINT, _shutdown)
    signal.signal(signal.SIGTERM, _shutdown)

    try:
        asyncio.run(main())
    except Exception as e:
        print(f"Unexpected error: {e}")
        _shutdown(None, None)
