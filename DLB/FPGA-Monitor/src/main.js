/**
 * Responsibility: Browser entry point and safe startup diagnostics.
 * Allowed dependencies: AppController, application stylesheet.
 * Forbidden responsibilities: Protocol, transport or state logic.
 * Public API: None.
 * Architecture invariants: AppController composes all service boundaries.
 */
import { AppController } from './app/AppController.js';
import './styles/main.css';
try { new AppController(document.getElementById('app')); }
catch (error) { document.getElementById('notice').textContent = `启动失败：${error.message}`; console.error(error); }
