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

## Lista de comprobación

Marca cada punto en una prueba con 4 jugadores (tú + 3 bots), o tú solo con los zorros.

### Lobby
- [ ] Apareces en **tu nido del lobby**, en la entrada, mirando a tus criaturas. El cartel del arco dice "Nido de …".
- [ ] Tus criaturas están en los **pedestales**, con su placa (nombre, rareza, producción) y el aro del color de la rareza (dorado si es favorita). Dan saltitos.
- [ ] Primera vez (sin datos guardados): una criatura de regalo y un **huevo de bienvenida** que nace en 2 minutos. El huevo del cuenco del nido **brilla** cuando está listo.
- [ ] El botón 🥚 **Nido** abre el panel: criaturas, incubadora, mejoras, decorar, misiones y tienda.
- [ ] Comprar una decoración la coloca en el nido y suma Belleza al cartel.
- [ ] En la plaza: el **portal** con el texto de la cola, el **cartel del ranking** y la **estatua del Huevo Comunitario** con su porcentaje.
- [ ] En la entrada de un nido ajeno aparece "Me gusta ❤" (G); en el tuyo, no.
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
- [ ] Alrededor del claro hay **12 árboles gigantes** con plataformas a tres alturas.
- [ ] Las **rampas** en espiral se suben andando y tienen barandilla. Los árboles sin rampa tienen **escalera** (se trepa).
- [ ] Los **puentes** tienen cuerdas; las **vigas** son estrechas y sin barandilla; los **caminos de piedras** se cruzan saltando.
- [ ] Las **setas rojas** te lanzan hacia arriba (suena "boing").
- [ ] La **tirolina** (E en el poste de lo más alto de un árbol grande) te baja hasta otro árbol.
- [ ] Al pisar la entrada de un **tobogán** bajas deslizándote hasta el suelo.
- [ ] Hay **cabañas**, copas de hojas, arbustos y troncos huecos donde esconderse.
- [ ] Caer de lo alto no hace daño.

### Incubación
- [ ] Las brasas, luciérnagas y **cajas sorpresa** se pueden recoger y **desaparecen del todo** al cogerlas (también los "?"). Reaparecen después.
- [ ] Con la bolsa llena, sale el aviso "Tu bolsa está llena" y las fuentes no se recogen.
- [ ] Hay brasas en lo alto de los árboles.
- [ ] Depositar en el huevo sube la barra y tu Afinidad. El huevo **late y suena** más deprisa cuanto más llena está la barra.
- [ ] A mitad de la incubación empieza la **lluvia de brasas doradas** (brasas doradas que dan el doble 25 s).
- [ ] Empujar (F) a alguien con la bolsa llena le hace soltar Calor (los novatos están protegidos sus 5 primeras rondas).
- [ ] Géiser: necesita dos jugadores pulsando a la vez.
- [ ] **Los bots no se quedan pegados** a las paredes ni a los troncos: rodean y suben rampas.

### Eclosión (10 s)
- [ ] El huevo tiembla y el foco salta entre los favoritos; la cámara no se bloquea.
- [ ] Con 7 o más jugadores salen **2 criaturas** (3 con 12 o más).

### Persecución
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
- [ ] Si un sonido no te gusta, cámbialo en `src/shared/Sounds.luau` (ver el comentario del principio).

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
