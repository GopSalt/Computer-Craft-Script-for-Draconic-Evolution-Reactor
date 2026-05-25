# ☢️ Draconic Reactor Advanced Control (ComputerCraft)

Advanced, highly stable, and failsafe control system for the **Draconic Evolution Reactor** using **ComputerCraft (CC: Tweaked)**. 
Features a responsive remote control panel, predictive safety shutdowns, and native support for a dedicated UPS (Uninterruptible Power Supply) buffer for reactor shields.

## ✨ Key Features

* **📡 Remote Telemetry & Control (Rednet):** Monitor and control your reactor from any dimension using Ender Modems. Includes a responsive UI designed for Advanced Monitors (fits perfectly on 3x2 screens without text overlap).
* **🛡️ Failsafe UPS Buffer Monitoring:** Natively supports a secondary Energy Pylon dedicated to feeding the Input Gate (Shields). If the UPS drops below 50%, the system forces an emergency shutdown, preventing tick-starvation explosions.
* **🛑 Predictive Overheat Protection:** Doesn't just wait for the critical temperature. Calculates the *Thermal Trend* (C/t) and shuts down the reactor if an overheat is mathematically inevitable.
* **📈 Smooth Anti-Oscillation Ramp-Up:** Intelligently adjusts the Flux Gate to reach the Target Generation without overshooting, eliminating output fluctuations (no "yo-yo" effect).
* **⚡ Zero-Waste Idle & Cooling:** When the reactor is offline or cooling down, the script feeds the input gate *exactly* the `fieldDrainRate` required, preventing millions of RF from being wasted in idle states.
* **⏸️ Instant Throttle Mode:** A single button on the remote panel instantly drops the Target Load to 0. The reactor maintains its temperature and shields but stops generating energy, allowing for safe pausing without a full shutdown cycle.

## 🚀 Quick Install

To run these scripts, you will need **Advanced Computers** and **Ender Modems**. Make sure the HTTP API is enabled in your modpack config (it usually is by default).

### Step 1: Reactor Core Setup
1. Place an Advanced Computer next to your Draconic Reactor.
2. Connect the following to the computer's network (via modems/cables): **Ender Modem**, the **Reactor** itself, **2x Flow Gates** (Input and Output), and **2x Energy Pylons** (one for Main Storage, one as a UPS buffer for the shields).
3. Open the computer terminal and run:
   ```bash
   pastebin run kZWZCE5a startup
   ```
4. The script will download the necessary files. Follow the on-screen prompts to assign your Pylons (Main and Buffer) and Flow Gates.

### Step 2: Remote Panel Setup
1. Place an Advanced Computer in a safe location at your base.
2. Attach an **Ender Modem** and connect an **Advanced Monitor** (ideal size: 3 blocks wide, 2 blocks high).
3. Open the computer terminal and run:
   ```bash
   pastebin run 5afcy4Y0 startup
   ```
4. Done! The script will launch and instantly sync with the reactor, displaying the dashboard.

-- Inspired by: https://github.com/StormFusions/Draconic-ComputerCraft-Program
