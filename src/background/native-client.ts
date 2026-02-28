/**
 * Native messaging client for TabX.
 * Communicates with the Swift native host via Chrome native messaging protocol.
 * The host is registered under com.tabx.host.
 */

import type { FromHostMessage, ToHostMessage } from "../types/index.js";

const HOST_NAME = "com.tabx.host";

export type MessageHandler = (msg: FromHostMessage) => void;
export type DisconnectHandler = (error?: string) => void;

export class NativeClient {
  private port: chrome.runtime.Port | null = null;
  private onMessage: MessageHandler;
  private onDisconnect: DisconnectHandler;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private reconnectDelayMs = 5000;

  constructor(onMessage: MessageHandler, onDisconnect: DisconnectHandler) {
    this.onMessage = onMessage;
    this.onDisconnect = onDisconnect;
  }

  connect(): void {
    if (this.port) return;
    try {
      this.port = chrome.runtime.connectNative(HOST_NAME);
      this.port.onMessage.addListener((msg: FromHostMessage) => {
        this.onMessage(msg);
      });
      this.port.onDisconnect.addListener(() => {
        const err = chrome.runtime.lastError?.message;
        this.port = null;
        this.onDisconnect(err);
        this.scheduleReconnect();
      });
    } catch (e) {
      this.port = null;
      this.onDisconnect(String(e));
      this.scheduleReconnect();
    }
  }

  disconnect(): void {
    if (this.reconnectTimer !== null) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    if (this.port) {
      this.port.disconnect();
      this.port = null;
    }
  }

  send(msg: ToHostMessage): boolean {
    if (!this.port) return false;
    try {
      this.port.postMessage(msg);
      return true;
    } catch {
      return false;
    }
  }

  get isConnected(): boolean {
    return this.port !== null;
  }

  private scheduleReconnect(): void {
    if (this.reconnectTimer !== null) return;
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      this.connect();
    }, this.reconnectDelayMs);
  }
}
