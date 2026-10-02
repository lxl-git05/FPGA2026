/**
 * Responsibility: Lightweight subscriptions shared by state and transport modules.
 * Allowed dependencies: None.
 * Forbidden responsibilities: Protocol, DOM, persistence.
 * Public API: on(), emit().
 * Architecture invariants: Events do not introduce cross-layer imports.
 */
export class Events {
  listeners = new Map();
  on(name, fn) {
    if (!this.listeners.has(name)) this.listeners.set(name, new Set());
    this.listeners.get(name).add(fn);
    return () => this.listeners.get(name).delete(fn);
  }
  emit(name, value) { for (const fn of this.listeners.get(name) ?? []) fn(value); }
}
