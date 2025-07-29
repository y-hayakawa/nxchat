#!/usr/bin/env python3

import asyncio
import os
import openai
import sqlite3
from sqlite3 import Connection

# Filename: tcp_llm_broadcast_server.py
# Persistent multi-client LLM broadcast server using SQLite

# Load OpenAI API key from environment
openai.api_key = os.getenv("OPENAI_API_KEY")

# Configuration
HOST = '0.0.0.0'
PORT = 12345
DB_PATH = 'chat_history.db'
# Allowed client IPs (set as strings)
ALLOWED_IPS = {
    '127.0.0.1',  # Localhost
    '192.168.1.2',
    '192.168.1.7',
    # Add other allowed IP addresses here
}
# Maximum prompt length (in characters)
MAX_PROMPT_LENGTH = 2000  # Adjust as needed

# Global state
clients = set()
conversation_history = []

# Database helper functions
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
            writer.write(message.encode() + b"\n")
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
            # Read raw data from client
            chunk = await reader.read(1024)
            if not chunk:
                break
            buffer += chunk

            # Process all complete messages (terminated by null)
            while True:
                idx = buffer.find(b'\0')
                if idx == -1:
                    # No complete message yet
                    break
                raw = buffer[:idx]
                buffer = buffer[idx+1:]

                text = raw.decode(errors='ignore')
                print(f"Received from {ip}: {text}")

                # Enforce prompt length limit
                if len(text) > MAX_PROMPT_LENGTH:
                    warning = f"[SERVER] Prompt too long ({len(text)} chars). Limit is {MAX_PROMPT_LENGTH}."
                    writer.write(warning.encode() + b"\n")
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

                # Save AI response
                conversation_history.append({"role": "assistant", "content": ai_message})
                save_message(db_conn, "assistant", ai_message)

                # Broadcast
                await broadcast(f"[{ip}]\n{text}\n")
                await broadcast(f"[ChatGPT]\n{ai_message}\n")
    except Exception as e:
        print(f"Error with {ip}: {e}")
    finally:
        print(f"Disconnecting {ip}")
        clients.discard(writer)
        writer.close()
        await writer.wait_closed()


async def main():
    db_conn = init_db(DB_PATH)
    server = await asyncio.start_server(
        lambda r, w: handle_client(r, w, db_conn),
        HOST, PORT
    )
    addr = server.sockets[0].getsockname()
    print(f"Serving on {addr}")

    async with server:
        await server.serve_forever()


if __name__ == '__main__':
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("Server shutting down...")

