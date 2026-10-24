# Probar el juego en Roblox Studio

El simulador (`sim/`) comprueba el equilibrio fuera de Roblox. Esta guía sirve para probar **el juego de verdad** dentro de Studio: tú solo con zorros de rival, o con varios jugadores que juegan solos (piloto automático), y con un panel de depuración para llegar rápido a cada situación.

Todo esto **solo funciona dentro de Studio**. En un servidor publicado, `Testing.enabled(...)` devuelve siempre `false`, el remoto `DebugCommand` se ignora y las fases duran lo normal.

## Cómo funciona en Studio (lobby y partida en un solo servidor)

El juego publicado tiene dos lugares: el **lobby** (tu nido, la tienda, la cola) y las **partidas** (la arena con el huevo). En Studio no se puede saltar de un lugar a otro, así que todo funciona en un solo servidor (modo *combinado*):

- El lobby y la arena están construidos a la vez, lejos el uno del otro.
- Apareces en tu nido del lobby. Pulsa **⚔️ JUGAR** (abajo) o pisa el círculo naranja del portal de la plaza.
- Cuando sale la partida, apareces en tu campamento de la arena. Al acabar la ronda vuelves a tu nido del lobby.
- Con **🔁 Seguir jugando: sí** (por defecto) vuelves a la cola solo. Si quieres quedarte en el lobby, ponlo en "no".
- Si no quieres esperar a la cola: **F7 → 🚀 Jugar ya**.

### ¿Por qué veo el lobby desde la partida?

Porque en Studio los dos lugares están en el mismo mundo: el lobby está a 1000 studs de la arena y, desde lo alto de los árboles, se ve a lo lejos. Es solo el modo de prueba. Al publicar con dos lugares (y sus IDs en `Config.Places`), el servidor de partida construye **solo la arena** y el del lobby **solo el lobby**: buscar partida te lleva a otro servidor con otro mapa.

### ¿Por qué no se ve nada en el editor y sí al pulsar Jugar?

Porque el mapa no está guardado en el archivo: lo **construyen los scripts al arrancar el servidor** (`MapService` llama a `ArenaBuilder`, `LobbyBuilder` y `NestBuilder`, que crean cada pieza con `Instance.new`). El `.rbxlx` solo lleva el código. En modo edición Studio no ejecuta scripts, así que el Workspace está vacío; al pulsar Jugar arranca el servidor, se ejecutan y aparecen el lobby y la arena. Así el mapa sale siempre igual que en el código (y el simulador y la página usan las mismas medidas). Cuando haya un mapa hecho a mano, se guardará en el archivo y se verá en el editor.

## Preparar la prueba

1. Sincroniza el proyecto (`rojo serve` + plugin, o abre el archivo `TheEggChooses.rbxlx`).
2. Elige cómo probar:
   - **Tú solo:** pulsa **Jugar** (F5). En la partida saldrán 3 **zorros del bosque** que persiguen al portador, así que hay alguien contra quien jugar.
   - **Con bots:** en la pestaña **Prueba** (*Test*), en el grupo **Clientes y servidores** (*Clients and Servers*), elige **Servidor local** y el número de jugadores (4 o más) y pulsa **Iniciar**. En algunas versiones de Studio este menú está en el desplegable que hay junto al botón de jugar, como *Servidor y clientes* o *Multijugador*.
3. Con varios jugadores se abren una ventana de servidor y una por jugador:
   - **Player1** eres tú y lo controlas con el teclado.
   - **Player2, Player3...** juegan solos con el **piloto automático**: en el lobby usan la tienda y se ponen en la cola; en la partida recogen Calor (también en lo alto de los árboles), depositan, persiguen a donde se vio al portador, roban con el prompt real y, si llevan la criatura, huyen por el parkour.

Como los bots son jugadores de verdad, recorren el mismo código que una persona: remotos, ProximityPrompts y validaciones del servidor. Si algo falla con ellos, también fallaría con jugadores reales.

## Ajustes (`Config.Testing`)

| Ajuste | Por defecto | Qué hace |
|---|---|---|
| `Autopilot` | `true` | Activa el piloto automático en Studio |
| `AutopilotOnFirstPlayer` | `false` | Si es `true`, Player1 también empieza en automático |
| `DebugTools` | `true` | Panel F7 y comandos de depuración en el servidor |
| `TimeScale` | `0.35` | Multiplica la duración de las fases en Studio (mínimo 5 s). Pon `1` para probar con los tiempos reales |

Con `0.35`, una ronda dura unos 2-3 minutos en lugar de 6. La eclosión (10 s) no se acorta.

## Teclas

| Tecla | Qué hace |
|---|---|
| **F8** | Activa o desactiva el piloto automático en esa ventana. Sirve para tomar el control de un bot o para soltar a Player1 |
| **F7** | Abre el panel de depuración |

Panel de depuración (F7):

| Botón | Efecto |
|---|---|
| 🚀 Jugar ya | Te mete en la cola y lanza la partida sin esperar a más jugadores |
| ⏭ Saltar fase | Termina la fase actual |
| 🔥 Llenar la barra | Suma Calor hasta la meta (prueba el umbral del 100 %) |
| 🥚 Ser el portador | Durante la persecución, te da la criatura |
| 🪙 +1 M Monedas / ✨ +1000 polvo | Para probar la tienda, las mejoras y la cría |
| 🐣 Criatura Épica / 🌈 Mítica | Añade una criatura a tu nido |
| ⏩ Abrir huevos ya | Termina la incubadora |
| 🌙 Noche de Saqueo on/off | Activa el evento en la ronda actual (o pon `Config.Testing.ForceLootNight = true` para todas) |
| 🌍 Llenar Huevo Comunitario | Llena la barra global en este servidor y reparte la criatura conmemorativa |
| 🏆 +3 robos en el ranking | Te suma 3 robos y refresca el cartel del lobby |
| 🔊 Probar sonidos | Suenan todos los sonidos seguidos, con su grupo, nombre y volumen en el botón. Pulsa otra vez para parar |

## Lista de comprobación

Marca cada punto en una prueba con 4 jugadores (tú + 3 bots), o tú solo con los zorros.

### Lobby
- [ ] **Tutorial** (con un perfil nuevo, o ⚙️ → Ver el tutorial otra vez): el cartel de arriba va diciendo qué hacer y la flecha de luz señala la brasa, el huevo, la rampa y al portador. "Saltar ✕" lo quita.
- [ ] **⚙️ Ajustes:** cambiar el volumen de efectos y de pasos se nota; el tamaño de la interfaz cambia todos los paneles; "Al hombro de otros: No" oculta las criaturas de los demás (la tuya no). Al volver a entrar se mantienen.
- [ ] **🎁 Regalo:** el botón brilla si hay regalo; al abrirlo da lo del día y se marca. Abrirlo otra vez el mismo día dice "Vuelve mañana".
- [ ] **Nombre:** elige una sola criatura en el panel, escribe un nombre y Guardar: sale en la placa del pedestal (y en el panel, con la especie debajo). "Quitar" vuelve al nombre de la especie.
- [ ] **🏁 Torre de la plaza:** pisa el cuadrado naranja junto al portal: sale el cronómetro. Sube por las plataformas, pisa los dos controles verdes y llega a la meta dorada: te dice el tiempo, guarda tu mejor marca, el cartel enseña el récord y la primera vez del día da 30 de polvo. Si te caes al suelo, se cancela.
- [ ] **💃 Emotes** (con una criatura al hombro): cada uno mueve la criatura y vuelve a su sitio; otro jugador lo ve igual.
- [ ] **Tienda 🛒:** el botón dorado de la derecha (debajo de las Monedas) se balancea y tiene la burbuja roja; abre la ventana con animación; las 5 secciones cambian; las tarjetas se ven bien en PC y en móvil (*Test → Device*). Con un número en `Config`, el botón verde enseña el precio de Roblox y abre su ventana de compra. Un pase comprado sale como "✔ ¡TUYO!" con confeti.
- [ ] **Pack de inicio:** con `Config.DevProducts.StarterPack` puesto, sale en el banner de Destacado con "Quedan 2 d 23 h"; al comprarlo llegan las Monedas, el huevo a la incubadora y el Gorro de novato, y deja de salir.
- [ ] **Fuegos artificiales:** al comprarlos, todos ven los cohetes sobre la plaza, el cartel con el nombre y la criatura del hombro gigante girando; si se compran dos, el segundo espera su turno.
- [ ] **Avisos de la tienda:** después de jugar una partida, con un huevo que tarde más de 2 min y la Incubadora Rápida configurada, al rato sale el aviso abajo con "¡Ver!" y X. No vuelve a salir en la sesión.
- [ ] **Plaza con Robux:** con un número en `Config.CosmeticProducts`, sale el botón verde R$ con el precio; en Studio la compra es de prueba y el artículo se entrega.
- [ ] **Plaza** (pestaña del panel del nido; con F7 → +1000 polvo): comprar un sombrero se lo pone a tu criatura al hombro (y lo ven los demás); comprar un tema pinta tu nido; "Quitártelo" lo deshace. Al salir, el nido libre vuelve a su aspecto normal.
- [ ] **👀 Mi nido** lleva la cámara a tus gradas y "↩ Volver" la devuelve. **🏡 Visitar** muestra los jugadores del lobby y te lleva a la entrada de su nido (sin que el anti-trampas te devuelva).
- [ ] **Móvil** (Studio: Prueba → Dispositivo → un teléfono): junto a una brasa, el huevo o el poste de una tirolina sale el botón grande naranja con su texto, y pulsarlo hace la acción.
- [ ] **Comandos de soporte** (en Studio funcionan para todos): escribe `!ayuda` en el chat; prueba `!ver Player1`, `!dar monedas Player1 500` y `!dar criatura Player1 Secret`.
- [ ] Galería de criaturas: abre un Huevo de Temporada o usa F7 hasta ver una Secreta (o mira `docs/criaturas.html`): Fénix, Unicornio, Aurora y Agujero Negro se ven bien.
- [ ] Apareces en **tu nido del lobby**, en la entrada, mirando a tus criaturas. El cartel del arco dice "Nido de …".
- [ ] Los nidos no se tocan entre sí: entre las vallas de dos nidos vecinos queda un hueco (antes se solapaban por los laterales).
- [ ] Los podios y la valla no parpadean al moverte (antes había piezas solapadas). Tus criaturas están en los **pedestales**, con su placa (nombre, rareza, producción) y el aro del color de la rareza (dorado si es favorita). Dan saltitos.
- [ ] Primera vez (sin datos guardados): una criatura de regalo y un **huevo de bienvenida** que nace en 2 minutos. El huevo del cuenco del nido **brilla** cuando está listo.
- [ ] El botón 🥚 **Nido** abre el panel: criaturas, incubadora, mejoras, decorar, misiones y tienda.
- [ ] Comprar una decoración la coloca en el nido y suma Belleza al cartel.
- [ ] En la plaza: el **portal** con el texto de la cola, el **cartel del ranking** y la **estatua del Huevo Comunitario** con su porcentaje.
- [ ] En la entrada de un nido ajeno aparece "Me gusta ❤" (G); en el tuyo, no.
- [ ] **Criatura al hombro:** en el panel del nido, 🦜 en una criatura la pone en tu hombro derecho (el botón se pone verde). Otra vez 🦜 la quita; 🦜 en otra la cambia. La ven los demás, va pegada al hombro al correr y saltar, y sigue ahí en la partida.
- [ ] Si compras la **🍀 Suerte del Lobby**, arriba sale la cuenta atrás y los huevos del nido que abra cualquiera salen mejores (sin IDs reales no se puede comprar en Studio: compruébalo al publicar).
- [ ] **Lobby decorado:** colinas y estanque fuera del muro, bosque detrás de los nidos, flores y farolillos en los caminos, bancos y rocas entre camino y camino. Nada tapa la entrada de un nido ni se mete dentro de su valla, y va fluido.
- [ ] Los precios de la tienda y de las mejoras son redondos (1.300, 4.600…) y ya no aparece la mejora Olfato.
- [ ] **Intercambio:** una Secreta recién conseguida no se puede ofrecer (sale el aviso de los 3 días). Tras 10 intercambios en un día, el siguiente se rechaza.
- [ ] 🐦 Bandada e intercambio funcionan en el lobby (el botón 🐦 desaparece en la partida).
- [ ] La ventana Output del servidor no muestra errores (si no activaste *API Services*, es normal un aviso de DataStore).

### Cola y partida
- [ ] **⚔️ JUGAR** te pone en la cola: el botón cambia a "✕ Salir de la cola" y arriba se ve "En la cola: N jugadores".
- [ ] Pisar el círculo naranja del portal también te pone en la cola.
- [ ] Si estás en una Bandada, entra toda la Bandada.
- [ ] Cuando sale la partida ("¡Partida encontrada!"), apareces en tu **campamento** de la arena con tus 3 favoritas a la vista.
- [ ] En la partida no aparecen los botones del nido ni de la Bandada, y la barra de arriba muestra la fase.
- [ ] Al acabar (resultados y, si toca, saqueo), vuelves a tu nido del lobby con lo ganado, y con "Seguir jugando: sí" vuelves a la cola.

### Arena y parkour
- [ ] Alrededor del claro hay **12 árboles gigantes** con plataformas de hasta 6 pisos (hasta 132 studs de alto).
- [ ] Las **rampas** en espiral se suben andando y tienen barandilla; en cada piso, un rellano te pasa a la plataforma. Los árboles sin rampa tienen **escalera** pegada a una cara de las plataformas: se trepa hasta arriba del todo y no choca con ellas.
- [ ] Los **puentes** tienen cuerdas; las **vigas** son estrechas y sin barandilla; los **caminos de piedras** se cruzan saltando.
- [ ] Las **setas rojas** te lanzan hacia arriba (suena "boing").
- [ ] La **tirolina** (E en el poste de lo más alto de un árbol grande) te baja hasta otro árbol.
- [ ] Al pisar la entrada de un **tobogán** bajas deslizándote hasta el suelo.
- [ ] Hay **cabañas**, copas de hojas, arbustos y troncos huecos donde esconderse.
- [ ] Caer de lo alto no hace daño.
- [ ] **Anti-trampas:** usar tirolinas, toboganes y setas (también con un poco de lag) **no** te devuelve hacia atrás. La ventana Output del servidor no muestra avisos `[AntiCheat]` jugando normal.

### Incubación
- [ ] Las brasas, luciérnagas y **cajas sorpresa** se pueden recoger y **desaparecen del todo** al cogerlas (también los "?"). Reaparecen después.
- [ ] Con la bolsa llena, sale el aviso "Tu bolsa está llena" y las fuentes no se recogen.
- [ ] Hay muchas brasas y alguna caja sorpresa en lo alto de los árboles.
- [ ] **Brasas por niveles:** en los pisos bajos, naranjas (5); desde la mitad del árbol (piso 3, 66 studs), **azules** brillantes (10); en la plataforma más alta de cada árbol, **moradas** (20). La bolsa sube lo que dice cada una.
- [ ] Con la lluvia dorada, las naranjas se vuelven doradas; azules y moradas mantienen su color (y también dan el doble).
- [ ] Depositar en el huevo sube la barra y tu Afinidad. El huevo **late y suena** más deprisa cuanto más llena está la barra.
- [ ] A mitad de la incubación empieza la **lluvia de brasas doradas** (brasas doradas que dan el doble 25 s).
- [ ] Empujar (F) a alguien con la bolsa llena le hace soltar Calor (los novatos están protegidos sus 5 primeras rondas).
- [ ] Géiser: necesita dos jugadores pulsando a la vez.
- [ ] **Los bots no se quedan pegados** a las paredes ni a los troncos: rodean y suben rampas.

### Eclosión (10 s)
- [ ] El huevo tiembla y el foco salta entre los favoritos; la cámara no se bloquea.
- [ ] Al romperse, el huevo desaparece y **sale la criatura en su sitio**, grande, girando y con luz de su rareza (si hay varias, en fila). Al empezar la persecución desaparece y vuelve el huevo.
- [ ] El elegido lee "¡Escóndete y aguanta hasta el final!" (ya no "¡Corre a tu nido!").
- [ ] Con 7 o más jugadores salen **2 criaturas** (3 con 12 o más).

### Persecución
- [ ] **Pistas:** si eres el portador y un ladrón (o un zorro) se acerca a menos de 22 studs, sale "⚠️ ¡Un ladrón cerca!" y suena un latido que se acelera. Si eres ladrón, ves huellas doradas del portador cuando estás cerca; se borran en unos segundos.
- [ ] Cada elegido tiene 10 s de inmunidad y los demás 4 s de espera.
- [ ] **Ya no hay que ir al nido:** el portador no tiene flecha y el aviso dice "Escondido · te verán en X s".
- [ ] **Señal:** cada 8 s, durante 2 s, el aura dorada del portador se ve **a través de los árboles** y suena un aviso. Queda una marca 📍 donde estaba y la flecha de los ladrones apunta allí.
- [ ] Fuera de la señal, el aura solo se ve si tienes al portador a la vista.
- [ ] En los **últimos 10 s** se ve a los portadores todo el rato ("¡Últimos segundos: todos a la vista!").
- [ ] **Robo por toque:** un toque de E junto al portador muestra "¡Robando! Quédate cerca…" y, si aguantas cerca 1,5 s, robas. Si el portador se aleja, sale "¡Se te ha escapado!".
- [ ] El portador ve "⚠️ ¡Te están robando! ¡Aléjate!".
- [ ] **Escudos:** el elegido empieza con 🛡️ (y otro si depositó 800 de Calor, y otro si es novato). Cada robo que le hagan rompe uno.
- [ ] Esprint (Shift) y relevo (Q) funcionan; ya no hay botón de puerta.
- [ ] **Zorros del bosque:** con menos de 6 jugadores salen zorros 🦊 que van a por los portadores (y suben por las rampas). Si te alcanzan, la criatura cae al suelo y cualquiera puede recogerla.
- [ ] Al acabar el tiempo, **quien tenga la criatura se la queda** ("🏆 ¡X se queda con …!").

### Resultados y eventos
- [ ] Cada ganador recibe su criatura (se ve en su nido del lobby al volver).
- [ ] Los demás reciben polvo de consolación; quien no hizo nada en la ronda ve "Sin consuelo".
- [ ] Huevo del Elegido: si el elegido pierde la criatura, aparece un huevo en su incubadora.
- [ ] 🌙 Noche de Saqueo: tras los resultados hay una fase "🌙 Saqueo" de 60 s con "Saquear" en las criaturas de los campamentos ajenos.

### Sonido
- [ ] Los **pasos** son golpecitos suaves (ya no chirrían) y cambian un poco en hierba y madera.
- [ ] Suenan: recoger Calor (más agudo si coges varias seguidas), depositar, bolsa llena, caja sorpresa, empujón, géiser, eclosión, ser portador, tira y afloja, robo, escudo roto, la señal, la cuenta atrás de los últimos 5 s, trampolín, tirolina, compras, cola y los clics de los botones.
- [ ] **Volumen equilibrado:** ningún sonido tapa a los demás ni se pierde; recoger brasas es suave y robar o ganar se oye claro. Los sonidos del parkour (trampolín, tirolina) se oyen bien aunque estén a unos metros.
- [ ] Si alguno sigue fuerte o flojo: F7 → 🔊 Probar sonidos, apunta su nombre y cambia su `Level` en `src/shared/Sounds.luau` (o el de todo su grupo en `Sounds.Groups`).

### Datos
- [ ] Con *API Services* activado: sal y vuelve a entrar y comprueba que se guardó todo.

## Si algo va mal

- **Un bot se queda quieto:** el piloto salta, se aparta y pide otro camino si no avanza. Si sigue quieto, pulsa F8 dos veces en su ventana.
- **Errores del piloto:** salen en la Output del cliente con el prefijo `[Autopilot]`. No rompen el juego.
- **La partida no sale:** en Studio sale en cuanto están en la cola todos los jugadores de la prueba o tras 8 s. También puedes usar F7 → 🚀 Jugar ya.
- **Quiero probar solo una cosa del lobby:** pon "Seguir jugando: no" y no pulses Jugar.

## Publicar los dos lugares

1. En el Creator Hub, dentro de tu experiencia, crea un segundo lugar (*Places → Add Place*). El de inicio será el **lobby** y el nuevo, el de las **partidas**.
2. Publica **el mismo archivo** en los dos lugares.
3. Pon los dos `PlaceId` en `Config.Places` (`Lobby` y `Match`) y vuelve a publicar en los dos.
4. En la configuración de cada lugar: el lobby con más jugadores por servidor (por ejemplo, 30) y el de partidas con 12.
