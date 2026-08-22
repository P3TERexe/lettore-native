# Standard di Sviluppo Frontend per Lettore

Questo documento definisce i criteri di qualità grafica, architetturale e di accessibilità per l'interfaccia Tauri 2 (WebView, vanilla ES modules).

---

## 1. Design System & Stile Visivo

* **Palette & Token CSS**: Tutte le variabili cromatiche, spaziature e raccordi devono essere definiti nel selettore `:root` in `styles.css`.
* **Aesthetics**:
  * Adottare un design scuro elegante (dark-mode raffinato, non grigio piatto).
  * Uso di sfondi semi-trasparenti con `backdrop-filter: blur(...)` (glassmorphism sottile).
  * Bordi delicati con trasparenza (`rgba(255, 255, 255, 0.08)`) ed ombre morbide (`box-shadow`).
* **Micro-Animazioni**:
  * Transizioni fluide (`transition: all 0.15s ease`) su hover, focus e stati attivi dei pulsanti.
  * Feedback visivo durante la sintesi (shimmer/pulse) e la riproduzione (indicatore onde audio).

---

## 2. Web Audio API & Ciclo di Vita

* **Prevenzione Race Conditions**:
  * Prima di invocare `source.stop()`, azzerare sempre `source.onended = null` per evitare trigger asincroni accidentali che farebbero avanzare la coda erroneamente.
  * Disconnettere sempre i nodi audio con `source.disconnect()` per prevenire memory leak.
* **Locking dell'Avanzamento Coda**:
  * Utilizzare un flag `_isAdvancing` nel `QueueController` per garantire che chiamate rapide o timer di polling non avviino richieste concorrenti di sintesi dello stesso item.

---

## 3. Accessibilità & Usabilità

* **Keyboard Navigation**:
  * Supportare scorciatoie rapide per il controllo (`Space` per Play/Pause quando non si scrive in textarea, `Esc` per fermare la riproduzione).
  * Utilizzare `aria-label` e attributi `title` espliciti su tutti i pulsanti iconici.
* **Finestra Flottante**:
   * Usare l'attributo `data-tauri-drag-region` sulla titlebar per il trascinamento (Tauri 2); NON usare `-webkit-app-region`, che è specifico di Electron e qui non ha effetto.
