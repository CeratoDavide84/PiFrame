# Risoluzione Problemi e Casi Noti (Troubleshooting & Known Issues)

Questo documento raccoglie diagnosi, cause radice e soluzioni per anomalie note legate all'ambiente di esecuzione desktop e web di **PiFrame**.

---

---

## Sottoagenti duplicati o con costo non disponibile

**Sintomo:** una chiamata di lettura del risultato o una notifica di completamento appariva come un altro sottoagente. La sessione figlia, mostrata con un nome come `reviewer#...`, poteva avere un costo separato dalla chiamata originale.

**Correzione:** PiFrame collega la chiamata `Agent` alla sessione figlia usando l'identità disponibile e mostra il nome dell'attività, il costo registrato e il modello effettivo. Le notifiche aggiornano un agente noto, senza crearne uno nuovo. I dati non disponibili restano `N/D`; stime e testo arbitrario non diventano costi effettivi. Se un collegamento è ambiguo, la sessione figlia resta visibile come non attribuita, senza una card agente aggiuntiva.

Il costo riportato da Pi e i costi dei sottoagenti attribuiti sono mostrati separatamente: Pi può già includere i secondi nel primo. La somma attribuita è indicata come parziale quando mancano dati; i costi delle sessioni non attribuite restano separati.

Per applicare una modifica al daemon, ricompilalo insieme all'app e riavvia il daemon solo quando non ci sono worker Pi attivi. Una build della sola app non aggiorna un daemon già in esecuzione.

---

## Errore "$ pi update --all /bin/sh: pi: command not found [codice 127]"

**Sintomo:** eseguendo un comando Pi dalla sezione *Impostazioni → Pi CLI* (ad es. `pi update --all`) o avviando l'installazione automatica su macOS, il processo terminava immediatamente con l'errore:
```
$ pi update --all
/bin/sh: pi: command not found

[Processo completato con codice 127 in 24ms]
```
Inoltre, anche se Pi era stato installato separatamente nel Terminale, l'app continuava a segnalare che Pi non era installato.

**Causa radice:**
Su macOS, le applicazioni grafiche avviate da Launch Services (Finder, Dock, Spotlight) ereditano da `launchd` una variabile d'ambiente `PATH` minimale ridotta a `/usr/bin:/bin:/usr/sbin:/sbin`. Gli eseguibili installati tramite lo script ufficiale curl (`~/.local/bin/pi`), Homebrew (`/opt/homebrew/bin/pi` o `/usr/local/bin/pi`) o manager di versione Node (`~/.nvm/...`) non si trovano in tali percorsi e le shell non interattive avviate da `/bin/sh` non caricano i file `.zprofile` o `.zshrc` dell'utente.

**Soluzione implementata:**
1. È stato introdotto il modulo centralizzato `PlatformEnvironment` sia nel client Flutter che nel daemon `agentd`, che arricchisce la variabile `PATH` includendo automaticamente `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/share/pi-node/current/bin` e la cartella del bundle applicativo, oltre a interrogare la shell di login dell'utente.
2. L'esecuzione dei comandi Pi risolve preventivamente il percorso assoluto dell'eseguibile `pi` ed esegue il processo fornendo l'ambiente arricchito senza dipendere dal percorso predefinito di `/bin/sh`.
3. L'installatore interno di PiFrame ora esegue lo script ufficiale `curl -fsSL https://pi.dev/install.sh | sh` (o `irm https://pi.dev/install.ps1 | iex` su Windows) e configura automaticamente i prerequisiti (Node.js standalone o tramite Homebrew) nel caso in cui non siano presenti nel sistema.

---

## macOS Gatekeeper: blocco applicazione non firmata o non verificata

**Sintomo:** all'apertura di `PiFrame.app` su macOS viene mostrato il messaggio: *"Impossibile aprire l'applicazione perché Apple non può verificare la presenza di software dannoso"* oppure non si avvia se non si concede il consenso esplicito.

**Causa radice e chiarimento sulla gratuità:**
macOS applica Gatekeeper a tutti i file ed eseguibili scaricati da Internet (assegnando l'attributo esteso `com.apple.quarantine`). Per consentire l'avvio immediato senza avvisi di sicurezza, Apple impone l'iscrizione a pagamento all'**Apple Developer Program ($99 USD all'anno)** con rilascio di un certificato *Developer ID Application* e notarizzazione automatica tramite i server Apple (`xcrun notarytool`).
Non esiste alcun meccanismo ufficiale gratuito fornito da Apple per firmare e notarizzare app distribuibili al pubblico (gli account Apple gratuiti generano unicamente profili di sviluppo locale validi per 7 giorni su dispositivi registrati).

PiFrame applica la firma ad-hoc (`codesign --force --deep --sign -`) nel workflow di release GitHub Actions, che soddisfa il requisito di firma obbligatorio per i chip Apple Silicon (`arm64`).

**Risoluzione:**
1. **Opzione Interfaccia Grafica (macOS 14 Sonoma e macOS 15 Sequoia):**
   - Fai doppio clic su `PiFrame.app`. Se appare l'avviso di Gatekeeper, premi *Annulla* o chiudi la finestra di dialogo.
   - Apri **Impostazioni di Sistema → Privacy e sicurezza**.
   - Scorri verso il basso fino alla sezione **Sicurezza**.
   - Troverai la dicitura *"L'apertura di PiFrame è stata bloccata..."*: fai clic su **Apri comunque** e inserisci la tua password o usa il Touch ID.
2. **Opzione Terminale (immediata in un solo comando):**
   ```bash
   xattr -cr /Applications/PiFrame.app
   ```
   Questo comando cancella ricorsivamente l'attributo `com.apple.quarantine` dal bundle applicativo. Da questo momento in poi, PiFrame si avvierà direttamente con un normale doppio clic.

---

## Comandi integrati di Pi assenti dal menu o inviati al modello

**Causa:** il comando RPC `get_commands` restituisce comandi di estensioni, prompt e skill, ma non il catalogo integrato della TUI Pi. Inoltre il composer inviava ogni testo come prompt, quindi un comando TUI non gestito poteva essere trattato come testo per il modello.

**Comportamento attuale:** il menu `/` include il catalogo integrato di Pi (`settings`, `model`, `tree`, `thinking`, `scoped-models`, `export`, `import`, `share`, `bug`, `copy`, `name`, `session`, `changelog`, `hotkeys`, `fork`, `clone`, `trust`, `login`, `logout`, `new`, `compact`, `resume`, `reload`, `quit`) insieme ai comandi RPC di estensioni, prompt e skill. In PiFrame, `/settings`, `/model`, `/tree`, `/thinking`, `/new`, `/compact`, `/reload`, `/copy`, `/name`, `/session`, `/fork`, `/clone`, `/resume` e `/quit` hanno azioni locali. Gli altri built-in sono identificati e mostrano un messaggio: non vengono inoltrati al modello perché richiedono UI o API della TUI non esposte dal worker RPC.

`/reload` chiama `ctx.reload()` tramite un comando interno di PiFrame e poi riapplica la policy di contesto. Durante una risposta o compattazione in corso viene rifiutato. Il catalogo è un mirror della lista di built-in Pi; aggiornarlo quando Pi aggiunge o rimuove comandi.

Verifica daemon:

```bash
pnpm --filter @piframe/agentd exec tsc --outDir .temp/builtin-command-tests
node --test apps/agentd/.temp/builtin-command-tests/commands/test/SlashReload.test.js
```

Il test usa un worker simulato; non prova le azioni UI o il reload contro una sessione Pi reale. Dopo aver aggiornato daemon e app, controlla il menu `/` e prova i comandi in una sessione di test.

---

## Review Changes: conteggi e diff errati

**Cause corrette:** il pannello aggiungeva `+1/-0` a ogni file toccato da Pi, anche se Git non lo segnalava come modificato; per un file tracciato pulito il fallback `--no-index` mostrava tutto il file come aggiunto. I file non tracciati non avevano conteggi, e i rename con percorso con spazi o caratteri speciali non venivano abbinati.

**Comportamento attuale:** Review usa solo l'elenco Git del daemon. I conteggi sono le righe nette `HEAD` -> working tree (inclusi staged e unstaged), anche per file non tracciati e per il repository senza `HEAD`. Un file pulito o mancante non genera un diff fittizio; un errore di caricamento viene mostrato come errore, non come assenza di differenze. I file binari hanno conteggio zero e mantengono il diff binario di Git.

Verifica da sorgente:

```bash
pnpm --filter @piframe/agentd exec tsc --outDir .temp/bugfix-tests
node --test apps/agentd/.temp/bugfix-tests/workspace/test/gitClient.test.js
cd apps/pi_frame
flutter test test/session_changes_review_test.dart
```

---

## Pannelli nascosti tornati visibili al riavvio

**Causa corretta:** la visibilità dei pannelli e il pannello sessioni erano solo in memoria, quindi ogni avvio ripartiva dal layout predefinito.

**Comportamento attuale:** PiFrame salva in `~/.piframe/layout.json` quali pannelli sono nascosti e se la barra sessioni è compressa. Durante Review Changes si salva il layout dell'utente, non quello temporaneo. Un file danneggiato viene ignorato e ripristina il layout predefinito.

Verifica da sorgente:

```bash
cd apps/pi_frame
flutter test test/layout_persistence_test.dart
```

---

## Chat input in ritardo quando si allargano i pannelli

**Causa:** durante il trascinamento del divisore il composer era dentro un `AnimatedSize` pensato per minimizzare ed espandere. Ogni cambio di dimensione durante il drag poteva essere animato, quindi il composer seguiva il divisore con ritardo.

**Comportamento attuale:** durante il trascinamento di un divisore il composer segue subito la misura del pannello. Minimizza/espandi mantiene l'animazione di 280 ms.

---

## Finestra all'avvio in alto a sinistra e stato massimizzato perso

**Cause corrette:** all'avvio Dart ripristinava la posizione salvata, quindi una finestra poteva aprirsi in un angolo. Su Windows il primo `Show()` usava `SW_SHOWNORMAL`, che annulla la massimizzazione appena applicata.

**Comportamento attuale:** la finestra si apre centrata con la dimensione normale salvata. Se era massimizzata o a schermo intero, lo stato viene ripristinato; le dimensioni normali non vengono sostituite da quelle massimizzate. Lo stato finale viene salvato prima della chiusura. La prima apertura senza file salvato usa la dimensione predefinita, centrata.

Verifica da sorgente:

```bash
cd apps/pi_frame
flutter test test/window_restore_test.dart test/startup_animation_and_window_test.dart
```

La release Windows va verificata dopo la build esplicitamente richiesta: questa verifica non avvia la finestra nativa.

---

## Timer dei comandi azzerato al cambio sessione e timeout fuorvianti

**Cause corrette:** il timer partiva dal montaggio del widget. Cambiare sessione ricreava il widget e riportava il conteggio a zero. La UI interpretava inoltre qualsiasi timeout maggiore di 1000 come millisecondi, confondeva `WaitMsBeforeAsync` con una scadenza e applicava il timeout del primo comando all'intero turno.

**Comportamento attuale:** il daemon conserva gli istanti di avvio di turno e comando e li include negli eventi e negli snapshot. Cambiare sessione o ricreare una card non cambia l'origine del timer. La durata si ferma al completamento o a Stop; viene usata la durata dell'esecutore quando disponibile, altrimenti il tempo osservato dal daemon. Per snapshot precedenti senza istanti di avvio non viene inventato un nuovo inizio.

Il timeout compare solo sulla singola azione e indica il valore richiesto negli argomenti. `timeout`/`timeoutSeconds`/`timeout_seconds` sono espressi in secondi, `timeoutMs`/`timeout_ms` in millisecondi; i suffissi espliciti `s` e `ms` sono rispettati, anche per valori frazionari. `WaitMsBeforeAsync`, valori non validi e campi assenti non generano un limite. Il timeout non viene applicato all'intero messaggio o turno.

Nel tool **bash integrato di Pi**, il timeout è opzionale, in secondi e senza valore predefinito. Il timeout RPC del daemon riguarda invece l'acknowledgement, non la durata del comando. Altri tool o estensioni possono avere limiti propri: PiFrame non impone un nuovo timeout né deduce default non comunicati.

Verifica da sorgente, senza ricompilare la release Windows:

```bash
cd apps/pi_frame
flutter test test/tool_timer_state_test.dart test/message_seconds_counter_test.dart test/tool_card_expanded_command_test.dart
```

---

## Sessioni non caricate all'avvio

**Cause osservate:** il provider poteva perdere la notifica di connessione perché si iscriveva agli eventi dopo aver letto lo stato iniziale. Inoltre il daemon scandiva sincronicamente i file delle sessioni e, con una cache fredda, ne leggeva il contenuto per intero prima di rispondere. Se la scansione superava 8 secondi, il client mostrava un timeout.

**Correzione:** il provider osserva la connessione prima di leggere lo stato e mostra gli errori invece di presentarli come elenco vuoto. Per il primo elenco il daemon riutilizza i metadati in cache e legge parti limitate dei file; completa l'indice in background e notifica la UI durante e dopo l'aggiornamento. Gli indici precedenti senza data di modifica dei metadati vengono verificati di nuovo in background. L'indicizzazione non modifica i file delle sessioni. Se un titolo non è presente o aggiornato in cache, può comparire temporaneamente l'ID o il titolo precedente, perché Pi può registrare la rinomina in qualsiasi punto del file. Se un file cambia mentre viene letto, viene verificato nuovamente dopo un intervallo crescente. Il tempo dipende dal numero di file e dalla velocità del filesystem.

Verifica da sorgente, senza avviare l'app:

```bash
pnpm --filter @piframe/agentd exec tsc --outDir .temp/startup-tests
node --test apps/agentd/.temp/startup-tests/sessions/test/FastSessionStartup.test.js
cd apps/pi_frame
flutter test test/daemon_state_test.dart
```

---

## Blocchi dei tool duplicati durante una risposta

**Causa:** Pi invia una chiamata tool nel messaggio dell'assistente e poi negli eventi di esecuzione. La chat mostrava entrambe le rappresentazioni; in alcuni casi la chiamata veniva anche copiata nel messaggio successivo.

**Correzione:** la chat riconcilia le chiamate per `toolCallId`, mantenendo stato, output e durata aggiornati. Le chiamate distinte restano visibili e quelle già registrate non vengono aggiunte di nuovo al termine del turno. Il comportamento vale anche per gli snapshot caricati durante l'esecuzione.

Verifica da sorgente, senza ricompilare la release Windows:

```bash
cd apps/pi_frame
flutter test test/transcript_message_types_test.dart test/session_tool_history_test.dart
```

---

## Azioni dell'agente mancanti dopo Stop o alla riapertura della chat

**Causa corretta:** i parser della chat riconoscevano solo `tool_call` e `tool_use`, non il formato Pi `toolCall` con argomenti in `arguments`. Alla ricostruzione della cronologia rimaneva il ragionamento, ma sparivano le card edit/write/bash/todo. Inoltre, gli output salvati come blocchi di testo nei messaggi `toolResult` non venivano ripristinati.

**Comportamento attuale:** messaggi live, snapshot e caricamento della cronologia riconoscono anche il formato Pi, conservando argomenti, output ed errori. Stop non rimuove le azioni già registrate. Le sessioni esistenti non richiedono migrazione: le card vengono ricostruite dai messaggi originali, se ancora presenti nel file della sessione.

Verifica da sorgente, senza ricompilare la release Windows:

```bash
cd apps/pi_frame
flutter test test/session_tool_history_test.dart test/session_reducer_test.dart test/transcript_message_types_test.dart
```

---

## Costo dei sottoagenti sempre a zero o fermo nel popup

**Cause corrette:** il daemon leggeva `usage.cost` solo sul contenitore JSONL, ignorando `message.usage.cost` dei messaggi Pi. Inoltre scartava tutte le sessioni con directory di lavoro temporanea, incluse quelle persistenti dei sottoagenti che usano un worktree. Il parser della notifica non riconosceva il tag Pi-subagents `<estimated_cost_usd>`. Il refresh poteva fermarsi perché i worker esterni al daemon risultavano già completati; il popup dei costi conservava inoltre i valori presenti al momento dell'apertura.

**Comportamento attuale:** il daemon somma i costi salvati nelle due forme, anche quando il file della sessione cresce, senza contare due volte la stessa voce. Legge anche le sessioni figlie persistenti nei worktree temporanei, senza inserirle nell'elenco normale delle sessioni; il parser riconosce il costo stimato emesso da Pi-subagents. Card e popup aperto ricevono gli aggiornamenti; il refresh ogni 5 secondi resta attivo mentre la sessione principale lavora o risultano sottoagenti in corso. Sono mostrati i costi registrati da Pi, non stime locali: un provider o modello senza prezzo può continuare a riportare zero.

Verifica da sorgente:

```bash
pnpm --filter @piframe/agentd exec tsc --outDir .temp/bugfix-tests
node --test apps/agentd/.temp/bugfix-tests/test/sessionCostPersistence.test.js
cd apps/pi_frame
flutter test test/subagent_cost_updates_test.dart test/subagents_feature_test.dart test/cost_breakdown_models_test.dart
```

La compilazione TypeScript usa una cartella temporanea: non modifica il bundle del daemon né la release Windows in uso.

---

## Modelli Copilot non autorizzati o tier di contesto ignorato

**Cause corrette:** il picker filtrava solo `enabledModels` locale, senza verificare le policy GitHub. Il limite di contesto era conservato in PiFrame ma non applicato a Pi; i controlli duplicati nella GUI e nel daemon usavano una soglia fissa all'80% e potevano ignorare gli errori.

**Comportamento attuale:** il daemon verifica le abilitazioni Copilot e rifiuta la selezione di un modello non autorizzato. Area di lavoro espone massimo personalizzato e margine percentuale; il worker applica la soglia alla compattazione nativa di Pi. Gli errori di applicazione non vengono più accettati come successo.

- Se il chip contesto nella chat mostra un tier ma non apre nulla, usa la build aggiornata: prima il composer poteva conservare un catalogo vuoto caricato prima della connessione al daemon. Ora ricarica i modelli al click e segnala esplicitamente i dati mancanti. Chat e Area di lavoro usano lo stesso selettore.
- Lo slider del massimo è nascosto finché non scegli **Custom** in Dimensione Contesto. I tier esatti (per esempio 272k) restano selezionabili; Custom usa passi di 50k. Il margine usa passi di 0,5%, da 0,5% a 25%.
- Se manca un modello Copilot, verifica account e abilitazione nella tua organizzazione. In caso di avviso di verifica, controlla rete e autenticazione con Pi; PiFrame non ripiega sul catalogo statico completo. La cache delle verifiche riuscite dura al massimo un minuto.
- Se compare **Pi non ha applicato il limite di contesto**, aggiorna Pi e riavvia il worker. Il controllo richiede `getSettings` nell'API estensioni; il test con runtime reale usa Pi 1.4.0.
- 5% significa compattare al **95%** del massimo scelto. Il valore predefinito 2,5% porta 200k a una soglia di 195k.
- Se non parte la compattazione, verifica che la compattazione automatica di Pi sia attiva. Modifica limite e margine a turno fermo.
- Se la compattazione fallisce o non riduce abbastanza il contesto, aumenta il limite o riduci il contesto conservato nelle impostazioni Pi. Un limite preventivo non può garantire un tetto di fatturazione: output singoli e richieste di riepilogo consumano token.

Verifica ripetibile da sorgente, senza chiamate a provider a pagamento: compila il daemon e avvia `node tools/scripts/smoke-context-policy.mjs`. Il test usa Pi reale con modello HTTP locale e directory temporanee isolate.

---

## 1. Windows: Finestra Bianca o Vuota all'Avvio (Blank / White Screen on Windows)

### Sintomi
All'avvio dell'applicazione desktop su Windows:
- La finestra di PiFrame si apre (con o senza cornice), il processo è attivo nel Task Manager e consuma memoria regolare.
- L'area di rendering (client area) rimane **completamente bianca** o **completamente nera**.
- L'applicazione non si blocca né genera eccezioni Dart nei log di sistema o nella console di debug (`flutter run`).
- **Comportamento identico su app vergini**: un'applicazione Flutter pulita generata con `flutter create` presenta lo stesso identico problema di rendering bianco.

### Causa Radice (Root Cause)
Il framework Flutter su piattaforma Windows si appoggia al backend grafico **ANGLE (Almost Native Graphics Layer Engine)** su Direct3D 11 (`EGL_PLATFORM_ANGLE_TYPE_D3D11_ANGLE`) e all'engine **Impeller / Skia**.

In presenza di:
1. **Driver di display virtuale o schermi secondari USB**:
   - `USB Mobile Monitor Virtual Display` (`ROOT\DISPLAY\0000`)
   - `IddSampleDriver`
   - Spacedesk, Duet Display, DisplayLink o monitor virtuali RDP/VNC
2. **Configurazioni ibride multi-GPU** (es. GPU integrata AMD Radeon/Intel + GPU dedicata NVIDIA GeForce RTX)
3. **Stato del Desktop Window Manager (DWM) corrotto** a seguito di uno spegnimento improvviso, crash di sistema (es. Evento 41 Kernel-Power) o risveglio da sospensione/ibernazione con perdita di contesto DirectX

Il Desktop Window Manager di Windows non finalizza la presentazione dello swapchain DirectX (`SwapChain11::present` o `EGLSurface`) verso la finestra figlia `FLUTTERVIEW`, lasciando visualizzato il background iniziale di sistema (bianco solido o nero trasparente) anche se l'albero dei widget e il motore di rasterizzazione di Flutter funzionano regolarmente.

*Riferimenti ufficiali alla issue di Flutter*:
- [flutter/flutter#149709: Flutter windows desktop screen comes up blank with 2 monitors connected to laptop](https://github.com/flutter/flutter/issues/149709)
- [flutter/flutter#160948: Impeller GPU calls fail to render on Windows (GLES)](https://github.com/flutter/flutter/issues/160948)
- [flutter/flutter#137321: Launching the app from a non-main monitor shows a white screen on Windows](https://github.com/flutter/flutter/issues/137321)

---

### Soluzioni e Risoluzione Rapida (Workarounds & Fixes)

#### Soluzione 1: Riavvio Pulito del Sistema (Clean Reboot)
Se l'anomalia compare dopo un crash, un aggiornamento driver o uno standby:
1. Riavvia Windows in modo completo (**Menu Start → Riavvia il sistema**, evitando l'avvio rapido "Fast Startup").
2. Al riavvio, il sottosistema DirectX / DWM ricrea i contesti EGL/ANGLE in modo pulito e l'interfaccia si avvia regolarmente.

#### Soluzione 2: Disabilitare o Scollegare i Display Virtuali / Secondari
Se il problema persiste dopo il riavvio:
1. Apri **Gestione Dispositivi** (`devmgmt.msc`).
2. Espandi la voce **Schede video** (Display adapters).
3. Se è presente un dispositivo virtuale (ad esempio `USB Mobile Monitor Virtual Display`, `IddSampleDriver` o simili):
   - Fai clic destro sul dispositivo virtuale e seleziona **Disabilita dispositivo** (o scollega l'applicazione di mirroring dello smartphone).
4. Avvia nuovamente PiFrame.

#### Soluzione 3: Assegnare la GPU Dedicata (Impostazioni Grafica Windows)
In sistemi con grafica integrata e scheda grafica dedicata (es. AMD + NVIDIA):
1. Apri **Impostazioni di Windows → Sistema → Schermo → Grafica**.
2. Aggiungi l'eseguibile `PiFrame.exe` (situato in `C:\Program Files\PiFrame\` o nella directory di installazione).
3. Fai clic su **Opzioni** e seleziona **Prestazioni elevate** (NVIDIA GeForce RTX) per forzare l'uso dell'adattatore D3D11 primario anziché il fallback software o integrato.

---

## 2. Connessione Remota: Pagina Fallback "Il daemon locale è attivo"

### Sintomi
Scansionando il QR code con lo smartphone o aprendo l'URL Tailscale / Cloudflare:
- Sul telefono appare una pagina con un riquadro statico recante il titolo *"PiFrame Daemon"* e il testo *"Il daemon locale è attivo e operativo su loopback"*, senza caricare l'interfaccia interattiva di PiFrame.

### Causa
Il daemon `pi-agentd` non trovava la directory compilata della web app Flutter (`apps/pi_frame/build/web`), attivando la pagina di cortesia statica di emergenza.

### Risoluzione
1. I percorsi di ricerca del daemon sono stati estesi per cercare automaticamente `apps/pi_frame/build/web`, `~/.piframe/web/` e la cartella `web/` adiacente all'eseguibile.
2. La web app compilata viene sincronizzata in `~/.piframe/web/` e inclusa negli installer di rilascio.
3. Se esegui da sorgenti, compila la versione web con:
   ```bash
   cd apps/pi_frame
   flutter build web --no-web-resources-cdn
   ```
   e copia i file generati in `~/.piframe/web/`.

## 3. Web App: Browser Integrato nel Browser

### Caso d'uso
Nella versione web di PiFrame visualizzata da smartphone o browser remoto, il pulsante e il pannello del *Web Browser integrato* sono stati intenzionalmente rimossi:
- Su dispositivi remoti (es. iPhone, Android, browser esterno), aprire un browser all'interno di una webview incorporata è ridondante e WebView2 è una tecnologia nativa desktop Windows.
- La modalità remota web espone unicamente le aree di lavoro pertinenti: **Chat**, **File Explorer** e **Git Changes**.

---

## 4. Daemon Non Raggiungibile o Errore di Connessione con Build da Sorgente

### Sintomi
Avviando l'eseguibile `PiFrame.exe` compilato manualmente da sorgenti (ad esempio da `apps/pi_frame/build/windows/x64/runner/Release/PiFrame.exe`):
- L'applicazione si avvia ma la lista sessioni mostra `TimeoutException after 0:00:08.000000`.
- Il bundle Release contiene `scanFastSnapshot` ma non `getCachedSnapshot`.

### Causa
Una build manuale di Flutter (`flutter build windows`) non ricompila il daemon. Il vecchio `session.list` attendeva la scansione filesystem prima di rispondere; il primo bundle aggiornato aggiungeva l'indice rapido, ma attendeva ancora tutta la sua scansione. Quel bundle contiene `scanFastSnapshot`, ma non `getCachedSnapshot`, quindi può ancora superare il limite UI di 8 secondi.

### Risoluzione
1. Dalla radice del monorepo, ricompila il daemon prima dell'app:
   ```powershell
   pnpm build:agentd
   ```
   La build Windows ora rifiuta il sidecar se manca o non contiene sia `scanFastSnapshot` sia `getCachedSnapshot`.
2. Ricompila Flutter. CMake copia il bundle aggiornato accanto a `PiFrame.exe`. Copia `node.exe` nella stessa directory se non è già presente.
3. Se il daemon è già in esecuzione, attendi la fine del lavoro attivo e usa **Impostazioni → Riavvia Daemon**. Ricompilare l'app non ricompila né arresta un daemon già avviato.

Il nuovo daemon risponde usando lo snapshot in memoria/cache e aggiorna l'indice in background; se la cache è fredda, attende il fast scan al massimo 250 ms, poi continua in background. Il controllo non legge né riscrive le sessioni Pi. Se l'errore resta dopo questi passaggi, verifica che `pi-agentd.cjs` accanto a `PiFrame.exe` contenga `getCachedSnapshot`; un solo rebuild Flutter non aggiorna `apps/agentd/dist/pi-agentd.cjs`.

---

## 5. Installazione Dipendenze: Errore `EBUSY: resource busy or locked, symlink` (Windows)

### Sintomi
Eseguendo `pnpm install` o `pnpm build:all` su Windows, l'installazione fallisce con:
```text
EBUSY: resource busy or locked, symlink ...
"tsc" non è riconosciuto come comando interno o esterno
```

### Causa
Un processo attivo (un'istanza di `PiFrame.exe` in esecuzione, il daemon `pi-agentd` o il terminale) mantiene bloccate le cartelle dei pacchetti del monorepo mentre `pnpm` tenta di creare i collegamenti simbolici. Di conseguenza l'installazione delle dipendenze viene interrotta prima di collegare il compilatore TypeScript (`tsc`).

### Risoluzione
1. Termina eventuali istanze dell'app o del daemon:
   ```powershell
   Stop-Process -Name "pi-agentd","pi-frame","PiFrame" -ErrorAction SilentlyContinue
   ```
2. Riesegui l'installazione delle dipendenze e la build:
   ```powershell
   pnpm install
   pnpm build:all
   ```

---

## 6. CI/Release: Test Flutter, GitHub Pages o bundle Windows

### Messaggio utente duplicato nella chat

L'interfaccia mostra subito il messaggio inviato. Quando il daemon riceve la conferma da Pi, riconcilia l'evento con la voce ottimistica invece di aggiungere una seconda riga. Se l'invio fallisce, la bolla conserva testo e allegati: usa **Riprova** oppure fai doppio clic sulla bolla per modificarla nel composer. Per verificare questa logica, esegui:

```bash
cd apps/pi_frame && flutter test test/session_reducer_test.dart test/failed_message_flow_test.dart
```

### Test Flutter falliti in CI

Il test `resolvePathForOsExplorer correctly resolves WSL and Windows paths` copre l'output di Windows/WSL, prodotto solo quando `Platform.isWindows` è vero. Linux usa la risoluzione POSIX: il test Windows viene saltato lì e un test POSIX separato verifica quel comportamento. Se il test fallisce, esegui prima il test mirato e poi la stessa suite Flutter e analisi usate dalla CI:

```bash
cd apps/pi_frame && flutter test test/transcript_rich_test.dart
```

Dalla radice del repository, esegui i wrapper per tutti i test Flutter e l'analisi Flutter:

```bash
node tools/scripts/test-flutter.js
node tools/scripts/lint-flutter.js
```

### GitHub Pages restituisce 404

In **Repository Settings → Pages**, imposta **Build and deployment → Source** su **GitHub Actions**. Se la configurazione Pages fallisce, il job ora segnala il fallimento invece di nasconderlo; controlla il relativo step e i permessi del repository.

### Release Windows segnala l'eseguibile mancante

CMake produce `PiFrame.exe` e l'installer usa lo stesso nome. Il controllo del bundle nella workflow Release deve cercare `PiFrame.exe` (non `pi_frame.exe`). Verifica la coerenza localmente con:

```bash
node --test tools/scripts/test-windows-release-name.test.mjs
```

### Build Linux fallisce perché manca WebKitGTK

Se CMake segnala `None of the required 'webkit2gtk-4.1;webkit2gtk-4.2;webkit2gtk-4.3' found`, manca la libreria di sviluppo richiesta dal plugin `webview_win_floating`. Su Ubuntu 24.04 installa:

```bash
sudo apt-get install libwebkit2gtk-4.1-dev
```

La workflow Release installa questo pacchetto sia nella validazione sia nella build Linux. Il `.deb` dichiara anche `libwebkit2gtk-4.1-0` come dipendenza runtime: installalo con `sudo apt install ./PiFrame-<version>-linux-amd64.deb` per risolvere le dipendenze.

Verifica le dichiarazioni dalla radice del repository:

```bash
node --test tools/scripts/test-windows-release-name.test.mjs
```

Per distribuire anche la dipendenza runtime corretta, crea una nuova release che includa questo fix. **Actions → Release → Run workflow** dal ramo `main` con un tag precedente (per esempio `v1.1.0`) usa le dipendenze di build della workflow aggiornata, ma lo script di packaging rimane quello del vecchio tag: il `.deb` così ricostruito non include la nuova dichiarazione runtime. Rieseguire soltanto il vecchio run usa ancora la workflow priva del fix.

### Build Linux fallisce perché manca libnotify

Il plugin notifier di Flutter per Linux richiede che `pkg-config` trovi `libnotify`. Installa il pacchetto di sviluppo prima della build:

```bash
sudo apt-get install libnotify-dev
```

I pacchetti Debian installati richiedono anche la dipendenza runtime `libnotify4`. La CI di release installa `libnotify-dev` per la validazione e la build Linux; il pacchetto `.deb` dichiara `libnotify4`.

---

## 4. Disconnessione Continua WebSocket (Code 4009) e Accumulo Snapshot nel Giornale

### Sintomi
- PiFrame continua a disconnettersi e riconnettersi all'infinito ("Client too slow / backpressure buffer exceeded 128MB", close code `4009`) all'apertura o all'avvio dell'applicazione con sessioni pinnate molto grandi (es. > 100 MB).
- Lo spazio su disco nella cartella del giornale (`~/.piframe/journal/<sessionId>/`) cresce progressivamente fino a decine di gigabyte (es. 30 GB con centinaia di file `snapshot.<seq>.json`).

### Cause Radice
1. **Trascritto non vincolato nello snapshot**: all'attach della sessione, `SnapshotBuilder.build()` serializzava l'intero storico dei messaggi nel payload snapshot WebSocket. Per sessioni con migliaia di messaggi e output di tool voluminosi (es. 130-145 MB), il frame superava la soglia di backpressure di sicurezza di 128 MB implementata in `connection.ts`, provocando la chiusura della connessione con codice 4009. Poiché le sessioni pinnate vengono riattaccate in automatico all'avvio, l'applicazione entrava in un loop continuo di riconnessione.
2. **Assenza di retention policy negli snapshot del demone**: `EventJournal` genera un checkpoint di snapshot ogni 500 eventi per consentire il resume rapido senza rileggere l'intero log eventi. `Spill.ts` serializzava gli snapshot con indentazione estesa (`null, 2`) e non implementava alcuna rotazione o pulizia dei file storici, nonostante il caricamento (`loadLatestSnapshot()`) legga esclusivamente il file snapshot più recente.

### Risoluzione Implementata
1. **Finestra vincolata per lo snapshot (`SnapshotBuilder.ts`)**:
   - `SnapshotBuilder` delimita il numero di messaggi inclusi nel frame snapshot iniziale ai 100 più recenti (`MAX_SNAPSHOT_ENTRIES = 100`).
   - I singoli campi testuali anomali (es. dump di file massicci nei tool) sono protetti con un limite di sicurezza (`MAX_ENTRY_TEXT_BYTES = 256 KB`), riducendo la dimensione del payload da oltre 130 MB a circa 1.6 MB ed eliminando qualsiasi rischio di congestione WebSocket o freeze dell'interfaccia.
2. **Pulizia automatica e retention (`Spill.ts`)**:
   - Gli snapshot vengono scritti come JSON compatto senza indentazione inutile.
   - La funzione `pruneOldSnapshots(retainCount = 2)` mantiene solo i due snapshot più recenti e viene eseguita sia a ogni nuovo checkpoint sia all'inizializzazione del giornale (`init`), eliminando automaticamente tutti i checkpoint orfani accumulati e liberando lo spazio disco occupato.

---

## 5. Scrollbar a Scatti / Saltellante al Caricamento dei Messaggi Storici

### Sintomi
- Dopo aver cliccato "Carica altri messaggi dalla cronologia", il thumb della scrollbar si muove in modo scattoso ed errato, saltando su e giù anche se l'utente continua a scorrere fluidamente nella stessa direzione.
- Il pulsante caricava una quantità limitata di messaggi (35 alla volta), costringendo a ripetuti click per navigare trascrizioni lunghe.

### Cause Radice
1. **Stima dinamica instabile delle estensioni (`estimateMaxScrollOffset`)**: Flutter calcola `maxScrollExtent` per `ListView.builder` stimando l'altezza totale sulla media dei soli elementi attualmente visibili a schermo. In un'interfaccia di chat/log in cui un messaggio breve occupa 40px e un blocco di codice o tool diff occupa 800px, l'altezza stimata del totale variava bruscamente (es. da 10.000px a oltre 100.000px) tra un frame di scroll e l'altro, facendo rimbalzare la posizione relativa del cursore.
2. **Salto post-caricamento arbitrario (`jumpTo(oldOffset + diff)`)**: al caricamento dei messaggi storici in testa alla lista, l'applicazione tentava un salto proporzionale a una differenza di `maxScrollExtent` priva di layout reale, proiettando il cursore a offset non validi o fuori scala.
3. **Rebuild completi dell'albero dei widget durante lo scroll**: il listener di notifica scroll invocava `setState` su `_userScrolledUp` su ogni aggiornamento di scroll, invalidando l'intera vista trascritta durante il trascinamento.
4. **Doppio incremento di `_visibleCount`**: sia il callback del bottone che il ciclo di `build()` incrementavano il contatore di visibilità in risposta all'inserimento dei nuovi messaggi.

### Risoluzione Implementata
1. **Aumento quantitativo di caricamento a 250 messaggi (~7x)**:
   - In `Dispatcher.ts`, la soglia massima per `session.getHistory` è stata alzata fino a 1000 elementi con default a 250.
   - Nel frontend (`daemon_providers.dart` e `transcript_view.dart`), il pulsante carica 250 messaggi per click, mentre l'apertura iniziale mantiene 35 messaggi rapidi e performanti.
2. **`SmartTranscriptChildDelegate` e cache altezze per ID**:
   - Implementato un delegate personalizzato con cache persistente delle dimensioni effettive dei widget (`_MeasureSize`), indicizzata per ID messaggio stabile.
   - La stima di scorrimento (`estimateMaxScrollOffset`) utilizza la somma degli elementi già misurati più la media storica stabile per quelli ancora fuori viewport, rendendo la progressione della scrollbar strettamente monotona e priva di oscillazioni.
3. **Ancoraggio e preservazione della posizione di lettura**:
   - Al click su 'Carica altri messaggi', l'applicazione traccia la coordinata a schermo del primo messaggio visibile tramite `_anchorKey` e calcola l'altezza dei messaggi inseriti sopra.
   - Viene applicata una compensazione dell'offset pari all'altezza aggiunta con rifinitura sub-pixel al post-frame callback: il messaggio che l'utente stava leggendo rimane perfettamente immobile nella stessa identica posizione sullo schermo, evitando di saltare all'inizio dello storico. I messaggi precedenti rimangono consultabili scorrendo verso l'alto.
   - Estesa la cache dei widget a 2000px (`ScrollCacheExtent.pixels(2000.0)`) per evitare continue distruzioni e ricreazioni di elementi di grandi dimensioni.
4. **`ValueNotifier<bool>` per il floating button**:
   - La comparsa e scomparsa del pulsante per tornare in fondo alla chat è reattiva tramite `ValueListenableBuilder`, evitando qualsiasi `setState` globale dell'intera vista durante lo scroll.

---

## 6. Menu Modello Multipli, Messaggio "Non Consegnato" Errato, Domanda dell'Agente Bloccata

### Sintomi
- Cliccando più volte sul selettore del modello mentre il menu non è ancora comparso, si aprivano più popup.
- Il primo messaggio dopo la riapertura di una sessione risultava "Invio non riuscito" anche se Pi lo aveva ricevuto e l'agente rispondeva (solo più tardi).
- Una domanda a scelta dell'agente (card sopra il composer) non permetteva di premere "Invia" né di interagire, bloccando la chat.

### Cause Radice e Risoluzione
1. **Selettore modello/thinking**: il catalogo veniva caricato in modo asincrono prima di `showMenu`, quindi ogni tap lanciava un nuovo menu. `composer.dart` ora ignora i tap mentre un selettore è in apertura/aperto (`_guardPicker`) e il caricamento ha un timeout di 10s, così il selettore non resta mai bloccato.
2. **Consegna falsa negativa**: Pi conferma `prompt` solo dopo il preflight (es. compattazione pre-prompt di una sessione grande, hook di estensioni), che può superare i 30s del daemon. `StdioPiTransport` ora considera un `prompt` con ack lento come accettato (`disposition: pending`); un eventuale rifiuto tardivo di Pi arriva come `worker.diagnostic`. Gli altri comandi mantengono il timeout con errore.
3. **Card domanda bloccata** (`extension_ui_dialog.dart` + `composer.dart`):
   - corpo (messaggio e opzioni) scrollabile con altezza massima: pulsanti Annulla/Invia sempre visibili anche con molte opzioni o testo lungo;
   - i pulsanti non dipendono più dall'esito del claim: solo "già in uso da un altro client" blocca la card; claim lento, fallito o offline non la disabilita (il daemon arbitra comunque la risposta);
   - dopo risposta, scadenza del timeout o richiesta non più presente sul daemon (`Request not found`) la card viene chiusa localmente, senza attendere l'evento `ui.resolved`;

---

## 7. Vibrazione della Chat all'Espansione delle Card Attività/Subagenti e Riapertura Automatica al Cambio Sessione

### Sintomi
- Espandendo o minimizzando le card di attività e sottoagenti la lista della chat "vibrava" vistosamente e si spostava su e giù.
- All'apertura o al cambio di sessione, la card delle attività o dei subagenti si riapriva automaticamente espansa occupando metà dell'altezza del pannello chat.

### Cause Radice
1. **Loop di correzione del controller bottom-anchored (`_BottomAnchoredScrollPosition`)**: Durante l'animazione di ridimensionamento del viewport (`AnimatedSize`), il controller rilevava una variazione di `maxScrollExtent` e invocava `correctBy` ad ogni frame. Questo invalidava il layout e scatenava `ScrollUpdateNotification`, che veniva erroneamente interpretata come uno scroll manuale dell'utente, alternando ciclicamente lo stato di `_userScrolledUp` e facendo oscillare il punto di ancoraggio.
2. **Doppio `AnimatedSize` annidato**: Sia `TranscriptView` che i widget interni `TodoPopDown` e `SubagentsPopDown` applicavano contestualmente un proprio `AnimatedSize`, generando animazioni fuori fase e conflitti di misurazione.
3. **Inizializzazione a zero dei contatori al cambio/apertura sessione**: `_lastActiveTodoCount` e `_lastRunningSubagentCount` partivano da zero all'apertura di ogni sessione; di conseguenza, la presenza di task o subagenti preesistenti veniva interpretata come un nuovo incremento, innescando l'auto-espansione automatica (`_activeBookTab = _ActiveBookTab.todos` o `subagents`). Inoltre `_activeBookTab` non veniva resettato a `none` durante il passaggio tra sessioni (`didUpdateWidget`).

### Risoluzione Implementata
1. **Stabilizzazione del layout e rimozione del loop di scroll notification**:
   - Rimosso il doppio `AnimatedSize` annidato: quando `hideBookTab: true` (gestito direttamente dalla vista trascrizione), `TodoPopDown` e `SubagentsPopDown` non annidano più un secondo `AnimatedSize`, eliminando il conflitto di misurazione e i calcoli fuori fase.
   - Rimossa la gestione spuria di `scrollDelta` priva di `dragDetails` in `_handleScrollNotification`, affidando l'aggiornamento di `_userScrolledUp` esclusivamente a gesti reali dell'utente (`UserScrollNotification` o trascinamento attivo con drag details).
   - Introdotto `_toggleBookTab` con isolamento programmatico (`_isProgrammaticScroll = true`) durante la transizione animata delle card (250ms), impedendo notifiche di scroll spuria.
2. **Minimizzazione predefinita all'apertura e al cambio di sessione**:
   - Tracciato l'ID di sessione attivo (`_trackedSessionId`); all'apertura iniziale o al cambio sessione (`didUpdateWidget`), `_activeBookTab` viene impostato di default a `_ActiveBookTab.none`.
   - I contatori di task e subagenti attivi vengono sincronizzati con i valori correnti della sessione al caricamento senza innescare auto-espansione, garantendo che le card rimangano normalmente minimizzate lasciando visibile l'intera chat con le pill compatte nella barra superiore.
