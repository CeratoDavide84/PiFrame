# Changelog

## [1.3.0](https://github.com/TrentiStefano/PiFrame/compare/v1.2.0...v1.3.0) (2026-10-31)


### Features

* **macos:** add macOS DMG packaging script and Gatekeeper instructions ([b56ea63](https://github.com/TrentiStefano/PiFrame/commit/b56ea63371ef4fb5a12f781a89f8eb9f4b110219))
* **macos:** add package:macos offline DMG generation script and docs ([895939e](https://github.com/TrentiStefano/PiFrame/commit/895939e15a722060a717afd342e38490dbfefb7a))
* **macos:** include DMG installation and first-run guide in installer ([9296412](https://github.com/TrentiStefano/PiFrame/commit/92964120edf610b93f4f05feef7b4ddfb7c898aa))
* **macos:** integrate native custom title bar with window traffic lights ([54ee14c](https://github.com/TrentiStefano/PiFrame/commit/54ee14cd25771c6f23b2460df0362b0590bc780f))


### Bug Fixes

* **cli:** resolve macOS environment PATH and support official curl installer with prerequisites ([9bbadbc](https://github.com/TrentiStefano/PiFrame/commit/9bbadbc3796dad33cb5bc18fc8b9bfa63a9e0129))
* **packaging:** probe login shell PATH and standard Flutter paths in macOS packager ([c3e02b5](https://github.com/TrentiStefano/PiFrame/commit/c3e02b5a3031d4e2fa316034c5b8149ca4c65031))

## [1.2.0](https://github.com/TrentiStefano/PiFrame/compare/v1.1.1...v1.2.0) (2026-10-30)


### Features

* **auth:** support Pi login and logout in chat ([da96003](https://github.com/TrentiStefano/PiFrame/commit/da9600301c6d4e047471d1f5ce46db4eec86fff4))
* **commands:** expose Pi built-ins in the chat composer ([c067e4c](https://github.com/TrentiStefano/PiFrame/commit/c067e4cc77e15576a5e6668d0f77603e4f53f84e))
* **packaging:** add windows installer build script and documentation ([7cce387](https://github.com/TrentiStefano/PiFrame/commit/7cce38707ed1d20d3ab9d41e037782b32f3fbcfc))


### Bug Fixes

* **build:** reject stale agentd bundles ([4f53162](https://github.com/TrentiStefano/PiFrame/commit/4f5316201cbf48075c9ce5e3f2337d5c4b5fcc54))
* **commands:** run /reload as a Pi resource reload, not model text ([f4af324](https://github.com/TrentiStefano/PiFrame/commit/f4af324277f7a9c9ef507e3ef61d3ba6da1d785c))
* **composer:** follow pane divider drags without trailing ([52459fa](https://github.com/TrentiStefano/PiFrame/commit/52459fab874dd963edcc4bf0ad277ebdc4eeae3d))
* **dialogs:** accept free text from select questions ([1f8de24](https://github.com/TrentiStefano/PiFrame/commit/1f8de24b39640c76865373cdc62838b57210230f))
* **interrupt:** return before agent becomes idle ([19255a9](https://github.com/TrentiStefano/PiFrame/commit/19255a986905b4af6e84c1f046df21887e21c64e))
* **layout:** keep hidden panes and sessions bar state across restarts ([aee7c3d](https://github.com/TrentiStefano/PiFrame/commit/aee7c3d2c7363b289eb2ab512f8fe895a28746cc))
* **review:** show real net line counts and no fabricated diffs ([2a57609](https://github.com/TrentiStefano/PiFrame/commit/2a57609ee69f350e446419a2a27e332f9d427ca0))
* **session:** resolve disconnect loops on large journals, add on-demand history pagination, and stabilize transcript scrollbar ([496c7ce](https://github.com/TrentiStefano/PiFrame/commit/496c7ce4cf3df43cd907e6af6f9ac73fe172a70f))
* **sessions:** preserve refreshes during indexing ([e04df0c](https://github.com/TrentiStefano/PiFrame/commit/e04df0c9f3b5fa54d97ba102c30f794959f6c8b6))
* **sessions:** prevent startup index timeouts ([77a9d12](https://github.com/TrentiStefano/PiFrame/commit/77a9d12a6d731d4d9d0b4b8199e9afe26e01fdab))
* **sessions:** remove glow from repository rows ([9bd7ddd](https://github.com/TrentiStefano/PiFrame/commit/9bd7dddda8cc3a6020e8f0d7a766bc48f6e470a7))
* **sessions:** reply from cached snapshot during refresh ([9805e99](https://github.com/TrentiStefano/PiFrame/commit/9805e9938fca02347e967c12bc499fda182effaa))
* **subagents:** avoid duplicate cards and false zero costs ([656b8cd](https://github.com/TrentiStefano/PiFrame/commit/656b8cdefe4f096ba609912f2dc3c29267ee0f53))
* **subagents:** restore recorded costs and keep cost displays live ([0de92ab](https://github.com/TrentiStefano/PiFrame/commit/0de92ab653a4168e55504263f5e7d63c05021bc6))
* **test:** resolve workspace root dynamically in UI capture tests and ignore misplaced dumps ([3bedbc8](https://github.com/TrentiStefano/PiFrame/commit/3bedbc8b79a6b0870e506ef81d09ad599e34eb61))
* **transcript:** align tool controls with reasoning ([6460093](https://github.com/TrentiStefano/PiFrame/commit/64600932d2b7519e0dd87cb574fcda6fc57ddb1b))
* **transcript:** eliminate chat vibration when expanding or minimizing activity and subagent cards ([6385a05](https://github.com/TrentiStefano/PiFrame/commit/6385a051fe3259e07387ec6af6d4f84f5cf7c0ce))
* **transcript:** keep activity and subagent cards minimized on session open and switch ([a4d1bbf](https://github.com/TrentiStefano/PiFrame/commit/a4d1bbf1b53db03e970f61d4b6554881013c9d77))
* **transcript:** keep book tab bar height stable ([6203d06](https://github.com/TrentiStefano/PiFrame/commit/6203d06b1ef3c9b8a31b9c5ae7fdb7f3a79f6cc2))
* **transcript:** preserve execution timers across session switches ([786b4ac](https://github.com/TrentiStefano/PiFrame/commit/786b4ac5319f10781a2cfedd911e8fdd31e03e80))
* **transcript:** preserve Pi tool actions after interruption and reopen ([90ea79a](https://github.com/TrentiStefano/PiFrame/commit/90ea79ac7208b4faf5f65ce9e6ccfe5f64ec05f7))
* **transcript:** prevent chat jumps when expanding cards ([f481373](https://github.com/TrentiStefano/PiFrame/commit/f481373d704cd40c412cadba4ea419c5bffca062))
* **transcript:** prevent duplicate tool cards ([b1c0aa3](https://github.com/TrentiStefano/PiFrame/commit/b1c0aa3c415345b00a2ba38de26bc72757630752))
* **transcript:** refresh height estimates after card toggles ([406e358](https://github.com/TrentiStefano/PiFrame/commit/406e35821f4a61a019c61951a34b4ac59ff6e6ab))
* **ui:** prevent duplicate menus and blocked agent prompts ([598f266](https://github.com/TrentiStefano/PiFrame/commit/598f266802fae4ac92ccf477759e9e85fed2f358))
* **window:** open centered and restore maximized state ([b5c177f](https://github.com/TrentiStefano/PiFrame/commit/b5c177f3bf799343ca7d1441fe59da6d6d237ee4))

## [1.1.1](https://github.com/TrentiStefano/PiFrame/compare/v1.1.0...v1.1.1) (2026-10-27)


### Bug Fixes

* **context:** enforce model tiers and compaction limits ([cc7c965](https://github.com/TrentiStefano/PiFrame/commit/cc7c965c537b25b4f780d28e75d53d084161dbcf))
* **linux:** declare required WebKitGTK dependencies ([f7f27f1](https://github.com/TrentiStefano/PiFrame/commit/f7f27f1a9927d393f8ea58333c1941e1aeed29b6))

## [1.1.0](https://github.com/TrentiStefano/PiFrame/compare/v1.0.0...v1.1.0) (2026-10-26)


### Features

* add code syntax highlighting, search, steer queue editing, and showcase ([0cbbd2e](https://github.com/TrentiStefano/PiFrame/commit/0cbbd2e95a19903bd5b15202a92001f5807ef5b6))
* add Pi CLI controls in settings, collapsible workspace panes, and integrated terminal ([ca6f420](https://github.com/TrentiStefano/PiFrame/commit/ca6f4208b1b0cd3205fe8c8a412601509700ba58))
* **app:** startup animation with logo assembly, framing audio and window size persistence ([e819f44](https://github.com/TrentiStefano/PiFrame/commit/e819f44f5782281bd5cb301026c97c02f7ea4b68))
* automatic update from the settings (check for updates button) ([a219053](https://github.com/TrentiStefano/PiFrame/commit/a219053540d0636ff9d5ae385b9e9ceecad4c053))
* **branding:** redesign app icon to 3d pie slice with cohesive crust and centered pi glyph ([59a9708](https://github.com/TrentiStefano/PiFrame/commit/59a97080a377c2fff16bfb796cc788c572ef5fd9))
* **browser:** add integrated web browser pane, fix nullability in session reducer, and resolve release diagnostics ([22d6524](https://github.com/TrentiStefano/PiFrame/commit/22d6524ba77334504e1248aae3e2f33f4ab4af85))
* **browser:** embed native Chromium WebView2 for live browsing ([50dd2db](https://github.com/TrentiStefano/PiFrame/commit/50dd2db3224030cae34cdf53e86a25d27a8205ea))
* **chat:** add attachment options, transcript chips with image lightbox, and drag-and-drop support ([31bd627](https://github.com/TrentiStefano/PiFrame/commit/31bd627bc326eb8719e136062d727d1ea0da205a))
* **composer:** add button and toggle to enlarge chat input window on long prompt ([b948b32](https://github.com/TrentiStefano/PiFrame/commit/b948b32522c5345bb6f047622370949738fabe72))
* **composer:** animate minimize chat input while agent is answering ([71db799](https://github.com/TrentiStefano/PiFrame/commit/71db799ba8423ec1896aae4424df1e7a1abe86b4))
* **composer:** dock model interaction card on input and improve file mentions ([7eb52d6](https://github.com/TrentiStefano/PiFrame/commit/7eb52d66a142512bdbf66cd1f45ffd9e00715c2a))
* **context:** pick context size for models with variable context pricing (luna, haiku) ([7fc73ec](https://github.com/TrentiStefano/PiFrame/commit/7fc73ec555ae6d8d438feff837a2bc700c7129e1))
* **daemon:** add session.delete command to agentd and pcp protocol ([0200da0](https://github.com/TrentiStefano/PiFrame/commit/0200da032b8abff3dab9258c605ad76b8e5a1a9b))
* **docs:** replace slideshow with live application run video and animated GIF showcase inspired by pi-gui ([6afa453](https://github.com/TrentiStefano/PiFrame/commit/6afa453951c41fdeba1a7b1a39f195166cec8200))
* **icon:** add application icons and design assets for branding and UI ([ce5fa9a](https://github.com/TrentiStefano/PiFrame/commit/ce5fa9a5364a412df0778bbf9e433491c5a7d44e))
* **instructions:** generate instruction files with Pi agent from popup dialog ([7013646](https://github.com/TrentiStefano/PiFrame/commit/701364655abeede595706916cff1de083aa083b7))
* **landing:** show latest 5 active sessions as quick launch in welcome page ([05e24ea](https://github.com/TrentiStefano/PiFrame/commit/05e24ea7993479d0a8c7e6072ec5ccdc8afc6f8b))
* **mcp:** click on mcp card to view available servers and toggle them with checkboxes ([f724dfd](https://github.com/TrentiStefano/PiFrame/commit/f724dfd0a2a82eb17c6d3e22c762b8ad952268f4))
* **notifications:** add system notifications when agent finishes or requires attention while unfocused ([292d046](https://github.com/TrentiStefano/PiFrame/commit/292d0464ef6a07ae7e38484778ed2e82080ce064))
* release stabilization fixes (fixes 1-10 complete with multi-model cost breakdown, desktop snackbars, and handoff doc) ([263ff97](https://github.com/TrentiStefano/PiFrame/commit/263ff977b125cc1f04f296c40a9baa9123f4576c))
* **release:** automate semantic desktop releases ([e6a3f97](https://github.com/TrentiStefano/PiFrame/commit/e6a3f971d90236a732eecb290a6c801aecddc291))
* **release:** chat message types, iPhone layout and remote fixes ([d54dc77](https://github.com/TrentiStefano/PiFrame/commit/d54dc7739b26869fee7d49e259f1e8ec6611194d))
* **remote:** add secure remote access via Tailscale and Cloudflare ([ca4b5e6](https://github.com/TrentiStefano/PiFrame/commit/ca4b5e6d87135f6e72eb6eb9734c3a13debdde29))
* **session:** add Review Changes pane with diff viewing and 50/50 layout split ([6973882](https://github.com/TrentiStefano/PiFrame/commit/69738823e88bb5cc124f05b599b7ed5bdccdeb58))
* **sessions:** add quick session creation, folder activity glow, and pinned sessions ([eaf86b1](https://github.com/TrentiStefano/PiFrame/commit/eaf86b1ce9c1b83bd9cc6047e1c8fa6680740cc0))
* **sessions:** edit repository instruction files directly from sessions sidebar ([ec559b3](https://github.com/TrentiStefano/PiFrame/commit/ec559b3277b47b5e93c85b91b9602baf2a1a54d1))
* **settings:** language dropdown in appearance tab to choose application language ([b01a7ae](https://github.com/TrentiStefano/PiFrame/commit/b01a7ae23dadedffee2ccbf6e292ad5a02c5a471))
* **setup:** prompt to install pi-coding-agent on first run if not found ([fb190a6](https://github.com/TrentiStefano/PiFrame/commit/fb190a6e867bcb013963ba793e27ff1413bfc26f))
* **subagents:** add popdown subagents panel with expandable progress windows, steering and stop controls ([69dd31e](https://github.com/TrentiStefano/PiFrame/commit/69dd31e255f034b1253dde50e112442cdee1c657))
* **terminal:** direct in-terminal typing and native OS terminal integration ([85c9f4c](https://github.com/TrentiStefano/PiFrame/commit/85c9f4cb2edcdbc09af5201b08a9a4f10d0aad36))
* **theme:** add configurable default light and dark themes with system theme tracking ([76f684d](https://github.com/TrentiStefano/PiFrame/commit/76f684d29cec9b3c2787a6ffce253df769a22988))
* **theme:** import VSCode JSON themes, persist selected theme, and improve composer interactions ([71bd4a2](https://github.com/TrentiStefano/PiFrame/commit/71bd4a2b4fa3fdf2da27febda14b0deedbede556))
* **themes:** custom theme editor with base selection, color customization and live preview ([c7ca619](https://github.com/TrentiStefano/PiFrame/commit/c7ca619ae9feafc64a0150457555fcc60f7fe80b))
* **todos:** UI to show agent todo list with interactive checkboxes in real time ([92a86a8](https://github.com/TrentiStefano/PiFrame/commit/92a86a88e720d9a68b19c767e443fc2b2d89b8c5))
* **transcript:** double click session name in chat header to rename ([83ccf2a](https://github.com/TrentiStefano/PiFrame/commit/83ccf2a590d6fe6b459b9af5cd93a6249f6f2b2a))
* **transcript:** support CTRL+click on file mentions to open in OS file explorer ([abbbc8f](https://github.com/TrentiStefano/PiFrame/commit/abbbc8f52c7979840be08e97d0558cbeda896893))
* **ui:** Bento workbench density, Catppuccin surfaces and companion tabs ([2447bb2](https://github.com/TrentiStefano/PiFrame/commit/2447bb2ae4507e81665b802426fc750493b7d1ab))
* **ui:** harden transcript scrolling, add VS Code treeview explorer, and optimize workspace layout ([cdeaf1a](https://github.com/TrentiStefano/PiFrame/commit/cdeaf1a9fb7135a17e2d1826cae3e262386a527b))
* **ui:** redesign Flutter client with Precision identity ([5aac5c3](https://github.com/TrentiStefano/PiFrame/commit/5aac5c31d29849ef9962b578cc608e8ddb8f95af))
* **UI:** UI redesign with pi-design-director, new UI layout and themes ([1035790](https://github.com/TrentiStefano/PiFrame/commit/10357908658d9a32834ea6deaa6e1ddc7828fe5e))
* **ui:** unified side-by-side book tabs bar with exclusive tab control and remove subagents card from header ([a467991](https://github.com/TrentiStefano/PiFrame/commit/a46799197e01c7094beb01959c5bdf0eca13fe39))
* **updates:** startup notification banner for Pi CLI and package updates ([a9edff0](https://github.com/TrentiStefano/PiFrame/commit/a9edff0f7d92d61333d24ce13744ee1a602533f5))
* **website:** update landing page, design docs, and UI screenshots for PiFrame Dark & Light themes ([fc4c185](https://github.com/TrentiStefano/PiFrame/commit/fc4c185353e457623a49d9861cd383dcaf07df0a))
* **workspace:** add repository file search, add-to-chat actions, and start trees collapsed ([eab673a](https://github.com/TrentiStefano/PiFrame/commit/eab673a585bfd737acc07567c1e91980e51f98e5))
* **workspace:** support WSL repositories and terminal, evict stale daemons ([e4ffaab](https://github.com/TrentiStefano/PiFrame/commit/e4ffaabdb2bbc5b3143f7bcb2f69c328797edb5a))


### Bug Fixes

* **app:** repair Pi session workflows ([3364069](https://github.com/TrentiStefano/PiFrame/commit/336406919300b67374d08c5326128c4f77c1dde7))
* **chat:** reconcile and recover failed prompts ([4f27df9](https://github.com/TrentiStefano/PiFrame/commit/4f27df9edb1c1dc408e4fdfdb0259ad365c4a747))
* **chat:** reconcile and recover failed prompts ([43625ca](https://github.com/TrentiStefano/PiFrame/commit/43625caf9acc0c72cef4f5535adbb4d5bee35bf2))
* **ci:** repair main-only release workflows ([d635b11](https://github.com/TrentiStefano/PiFrame/commit/d635b1105fb378c62603546f7a988b5472b3f07c))
* **composer,agentd:** prevent steer queue double-send on agent stop, model change, and resend (Item 11) ([4059c94](https://github.com/TrentiStefano/PiFrame/commit/4059c94ffb00529f65516b8fe8d2959fc0f992d8))
* **composer:** add pointer glow to minimized chat input card and expand after 5s or click ([73b296f](https://github.com/TrentiStefano/PiFrame/commit/73b296f6569ddc40004ba64df9d6a352cd99713a))
* **composer:** match minimized interrupt button and label color with maximized stop button ([91f9e93](https://github.com/TrentiStefano/PiFrame/commit/91f9e930af46fd8fb8c1314c98bd615ff9c4cf2c))
* **daemon,transcript:** resolve daemon disconnect loop, stuck thinking/todos, and settings loader ([fc867ae](https://github.com/TrentiStefano/PiFrame/commit/fc867ae6b3b8594115414053ca103bd84a026664))
* **desktop:** split startup audio behind platform stubs and keep forks listed ([a48dab8](https://github.com/TrentiStefano/PiFrame/commit/a48dab87a97a244c96f8a773f98388e1108825e7))
* release workflow for automated builds and publishing improvements ([c486e3e](https://github.com/TrentiStefano/PiFrame/commit/c486e3e2bd4062e6ccc499f21f7904fd751c98d6))
* **release:** re-sign macOS app bundle after injecting daemon and node binaries ([eefb6ae](https://github.com/TrentiStefano/PiFrame/commit/eefb6ae11e2b6b0a6f98f661346219c83faa656e))
* **remote:** preserve remote enabled on restart and fix host allowlist ([e979f02](https://github.com/TrentiStefano/PiFrame/commit/e979f027a0f8ca7bdb45d121316f8b07331f40a6))
* **session:** index subsessions and maintain cumulative session cost across turns ([72f5a20](https://github.com/TrentiStefano/PiFrame/commit/72f5a2006935ea026877789ee0847ad3fc7afb04))
* **session:** persistenza del costo e metadati alla riapertura e avvio ([0d713d8](https://github.com/TrentiStefano/PiFrame/commit/0d713d872e8c75b61f70eb05b4639e223e8a2c70))
* **sessions:** filter out subagent subsessions from sessions sidebar and daemon index ([69a927e](https://github.com/TrentiStefano/PiFrame/commit/69a927e8543e7a6fd395e9c31a1c40e98f6bbc18))
* **sessions:** separate generating glow from active semaphore, add delete confirmation and repo removal ([3979fed](https://github.com/TrentiStefano/PiFrame/commit/3979fedb22dc13d72f9f9b0722e778ed6de07c4e))
* **sidebar:** show working indication and animation on pinned sessions ([e0e9782](https://github.com/TrentiStefano/PiFrame/commit/e0e978246a6ddca9d30879c12f779be168b7cb20))
* **stats:** update context usage and session cost in real time like TUI ([3c40887](https://github.com/TrentiStefano/PiFrame/commit/3c4088772eaa89ef15ee844a01463eaed59b276f))
* **subagents:** fix individual card collapse, fallback pricing, and running status reconciliation ([3e081fd](https://github.com/TrentiStefano/PiFrame/commit/3e081fd5e7a0e24cfba0831525f205c45ed35fe3))
* **subagents:** visualizzazione in tempo reale con costo e booktab dedicato ([3a90660](https://github.com/TrentiStefano/PiFrame/commit/3a90660dc858c89987a983cb509a15224f76890a))
* **terminal:** enable hardware typing in integrated terminal ([ea6998b](https://github.com/TrentiStefano/PiFrame/commit/ea6998b63e6d6dcf86b7b61be666587a91092e17))
* **themes:** improved readability for default dark and light themes ([2eb246e](https://github.com/TrentiStefano/PiFrame/commit/2eb246e198cf1d9eb346748072281758f2b19826))
* **timeline:** show full terminal command when expanded and add duration counter with timeout ([c545694](https://github.com/TrentiStefano/PiFrame/commit/c5456941939e950114c1445ba27b204993cc147a))
* **todos:** parsing robusto di oggetti non quotati e sincronizzazione stato completato ([1dfab15](https://github.com/TrentiStefano/PiFrame/commit/1dfab15657d60ba6135b2c6bd7a1eb43c5062a85))
* **todos:** prevent task counter runaway and duplicate creation during streaming ([f0843e4](https://github.com/TrentiStefano/PiFrame/commit/f0843e47271725760064755691bcfba7f8db0323))
* **todo:** support chat transition notifications and direct id/status updates ([0b6fd43](https://github.com/TrentiStefano/PiFrame/commit/0b6fd437ad520ff8de2ee7cfbad9da5b9fa68721))
* **transcript:** enable multi-paragraph mouse selection, clickable markdown links, and filter internal noise ([3eebf7b](https://github.com/TrentiStefano/PiFrame/commit/3eebf7b39ce469dc07da9aebde6bf3ba2734e289))
* **transcript:** persist thinking and tool timelines, fix stream auto-scroll and collapse tool cards by default ([ba52923](https://github.com/TrentiStefano/PiFrame/commit/ba529235f4d9d56dd786f5bcbdc753fe65ce92c0))
* **transcript:** right-align task timestamps and normalize spacing between intermediate blocks ([0acd6b4](https://github.com/TrentiStefano/PiFrame/commit/0acd6b4c69cd7e6b4b5c15a00f9a10717b804b5b))
* **transcript:** save session rename on enter and preserve expanded thinking blocks ([e7eab61](https://github.com/TrentiStefano/PiFrame/commit/e7eab61480f3e3cf979248d27fc86dd888a6de0a))
* **ui:** improve activities panel, subagents popup, multi-tier cost breakdown, and task notifications ([64e1c1a](https://github.com/TrentiStefano/PiFrame/commit/64e1c1a61a5713101e5124362c53f2b147989d2d))
* **ui:** polish subagent & todo panels, fix inline code wrap and timer ([7a0f745](https://github.com/TrentiStefano/PiFrame/commit/7a0f745c583c1cbffcfef1706de730d1b2b26f91))
* **ui:** rimossa card attivita dalla lista info chip nella session title card e migliorata gestione espansione subagenti ([16601af](https://github.com/TrentiStefano/PiFrame/commit/16601af5b4da097689fbb4b748a7baa087ef7b21))
* **ui:** update CrustMark to official 3D pie slice icon and record real Flutter app run for showcase ([3b83e6c](https://github.com/TrentiStefano/PiFrame/commit/3b83e6c618f35a7c035fe1c21ebeb5003f6445bc))
* **web:** make remote web client usable and drop the in-app browser on web ([972ab29](https://github.com/TrentiStefano/PiFrame/commit/972ab29e7f6d5f9ccb5761f62375d2285ca4a8b2))
* **workspace:** include untracked new files in git changes tab and add .md preview toggle ([9ba1aeb](https://github.com/TrentiStefano/PiFrame/commit/9ba1aebe1a3e391e4d5f31217a0e0bd3f1a50364))
* **workspace:** use null-aware element for trailing widget in git section header ([0bac8cc](https://github.com/TrentiStefano/PiFrame/commit/0bac8ccc69b09f010d57c536bf5a9b6098e99324))

## [1.3.0](https://github.com/TrentiStefano/piframe/compare/v1.2.0...v1.3.0) (2026-10-12)


### Features

* **composer:** dock model interaction card on input and improve file mentions ([7eb52d6](https://github.com/TrentiStefano/piframe/commit/7eb52d66a142512bdbf66cd1f45ffd9e00715c2a))
* **sessions:** add quick session creation, folder activity glow, and pinned sessions ([eaf86b1](https://github.com/TrentiStefano/piframe/commit/eaf86b1ce9c1b83bd9cc6047e1c8fa6680740cc0))
* **transcript:** double click session name in chat header to rename ([83ccf2a](https://github.com/TrentiStefano/piframe/commit/83ccf2a590d6fe6b459b9af5cd93a6249f6f2b2a))
* **workspace:** add repository file search, add-to-chat actions, and start trees collapsed ([eab673a](https://github.com/TrentiStefano/piframe/commit/eab673a585bfd737acc07567c1e91980e51f98e5))


### Bug Fixes

* **release:** re-sign macOS app bundle after injecting daemon and node binaries ([eefb6ae](https://github.com/TrentiStefano/piframe/commit/eefb6ae11e2b6b0a6f98f661346219c83faa656e))
* **transcript:** enable multi-paragraph mouse selection, clickable markdown links, and filter internal noise ([3eebf7b](https://github.com/TrentiStefano/piframe/commit/3eebf7b39ce469dc07da9aebde6bf3ba2734e289))
* **workspace:** use null-aware element for trailing widget in git section header ([0bac8cc](https://github.com/TrentiStefano/piframe/commit/0bac8ccc69b09f010d57c536bf5a9b6098e99324))

## [1.2.0](https://github.com/TrentiStefano/piframe/compare/v1.1.0...v1.2.0) (2026-10-12)


### Features

* **icon:** add application icons and design assets for branding and UI ([ce5fa9a](https://github.com/TrentiStefano/piframe/commit/ce5fa9a5364a412df0778bbf9e433491c5a7d44e))


### Bug Fixes

* release workflow for automated builds and publishing improvements ([c486e3e](https://github.com/TrentiStefano/piframe/commit/c486e3e2bd4062e6ccc499f21f7904fd751c98d6))

## [1.1.0](https://github.com/TrentiStefano/piframe/compare/v1.0.0...v1.1.0) (2026-10-12)


### Features

* **release:** automate semantic desktop releases ([e6a3f97](https://github.com/TrentiStefano/piframe/commit/e6a3f971d90236a732eecb290a6c801aecddc291))
* **ui:** harden transcript scrolling, add VS Code treeview explorer, and optimize workspace layout ([cdeaf1a](https://github.com/TrentiStefano/piframe/commit/cdeaf1a9fb7135a17e2d1826cae3e262386a527b))
* **ui:** redesign Flutter client with Precision identity ([5aac5c3](https://github.com/TrentiStefano/piframe/commit/5aac5c31d29849ef9962b578cc608e8ddb8f95af))
* **UI:** UI redesign with pi-design-director, new UI layout and themes ([1035790](https://github.com/TrentiStefano/piframe/commit/10357908658d9a32834ea6deaa6e1ddc7828fe5e))


### Bug Fixes

* **app:** repair Pi session workflows ([3364069](https://github.com/TrentiStefano/piframe/commit/336406919300b67374d08c5326128c4f77c1dde7))
* **ci:** repair main-only release workflows ([d635b11](https://github.com/TrentiStefano/piframe/commit/d635b1105fb378c62603546f7a988b5472b3f07c))
