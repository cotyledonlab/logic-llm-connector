# Mackie Control setup

Logic LLM Connector uses Logic Pro's built-in Mackie Control support. The
Companion must be running whenever Logic uses the control surface because it
owns both virtual MIDI ports for its process lifetime.

## Add the control surface

1. Build and open `build/Logic Companion.app`.
2. In Logic Pro, choose **Logic Pro > Control Surfaces > Setup**.
3. Check the Companion menu. If it reports **Mackie Control: Configured**, stop;
   setup is already complete.
4. If it reports a conflict, remove only the control-surface assignments that
   use `Logic LLM Connector Out` or `Logic LLM Connector In`. Do not use
   **Rebuild Defaults**, because that affects every control surface.
5. In the Control Surfaces Setup window, choose **New > Install**.
6. Select **Mackie Control**, then click **Add**. If Logic warns that another
   Mackie Control exists, add this one only when that other device is unrelated
   and uses different ports.
7. Select the new device and set its ports:

   - Input Port: `Logic LLM Connector Out`
   - Output Port: `Logic LLM Connector In`

8. Keep the Setup window visible and run `logic_doctor`, or check the Companion
   menu. The configuration is accepted only when one Mackie Control owns both
   ports and no second assignment uses either port.

Logic's Input Port receives the Companion's virtual source (`Out`), while its
Output Port sends to the Companion's virtual destination (`In`). Apple documents
manual device installation under **New > Install** and exposes both port values
as Device parameters in the Setup window.

## Teardown

1. Open **Logic Pro > Control Surfaces > Setup**.
2. Select the Mackie Control whose ports are the two Logic LLM Connector ports.
3. Delete that device in Logic, leaving unrelated control surfaces untouched.
4. Keep the Setup window visible and run `logic_doctor`; the Mackie check should
   report **missing**, not **conflicting**.

Stopping the Companion removes its live virtual endpoints but does not remove
Logic's saved assignment. Use the steps above when permanent teardown is
intended.

## Recovery

- **Ports are absent:** keep the Companion running. It independently recreates
  each stable endpoint on its next status refresh.
- **Doctor reports unknown:** grant Accessibility access if requested, open
  Logic, and leave the Control Surfaces Setup window visible with the device
  selected.
- **Doctor reports conflicting:** remove every split, duplicate, or non-Mackie
  assignment using either connector port, then add one Mackie Control with the
  exact port pair.
- **Logic shows an offline port after a Companion restart:** wait for both
  endpoints to reappear, reopen Setup, and reselect the same stable port names.
  Do not create a duplicate device.

References: [Apple: Add a control surface to Logic Pro](https://support.apple.com/en-gb/guide/logicpro/ctls718ddc0e/mac),
[Apple: Control surface Device parameters](https://support.apple.com/guide/logicpro/device-parameters-ctls718dd91b/mac).
