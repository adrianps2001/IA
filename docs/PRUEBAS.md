# Probar el juego en Roblox Studio

El simulador (`sim/`) comprueba el equilibrio fuera de Roblox. Esta guía sirve para probar **el juego de verdad** dentro de Studio, con varios jugadores que juegan solos (piloto automático) y un panel de depuración para llegar rápido a cada situación.

Todo esto **solo funciona dentro de Studio**. En un servidor publicado, `Testing.enabled(...)` devuelve siempre `false`, el remoto `DebugCommand` se ignora y las fases duran lo normal.

## Preparar la prueba

1. Sincroniza el proyecto (`rojo serve` + plugin, o `rojo build -o TheEggChooses.rbxlx`).
2. En Studio: **Test → Clients and Servers**, elige **4 jugadores** (o más) y pulsa **Start**.
3. Se abren una ventana de servidor y una por jugador:
   - **Player1** eres tú y lo controlas con el teclado.
   - **Player2, Player3...** juegan solos con el **piloto automático**: recogen Calor, depositan, persiguen, roban con el prompt real, defienden su nido y compran en la tienda al acabar.

Como los bots son jugadores de verdad, recorren el mismo código que una persona: remotos, ProximityPrompts y validaciones del servidor. Si algo falla con ellos, también fallaría con jugadores reales.

## Ajustes (`Config.Testing`)

| Ajuste | Por defecto | Qué hace |
|---|---|---|
| `Autopilot` | `true` | Activa el piloto automático en Studio |
| `AutopilotOnFirstPlayer` | `false` | Si es `true`, Player1 también empieza en automático |
| `DebugTools` | `true` | Panel F7 y comandos de depuración en el servidor |
| `TimeScale` | `0.35` | Multiplica la duración de las fases en Studio (mínimo 5 s). Pon `1` para probar con los tiempos reales |

Con `0.35`, una ronda dura unos 4-5 minutos en lugar de 12. La eclosión (30 s) no se acorta, porque es un espectáculo con su propio ritmo.

## Teclas

| Tecla | Qué hace |
|---|---|
| **F8** | Activa o desactiva el piloto automático en esa ventana. Sirve para tomar el control de un bot o para soltar a Player1 |
| **F7** | Abre el panel de depuración |

Panel de depuración (F7):

| Botón | Efecto |
|---|---|
| ⏭ Saltar fase | Termina la fase actual |
| 🔥 Llenar la barra | Suma Calor hasta la meta (prueba el umbral del 100 %) |
| 🥚 Ser el portador | Durante la persecución, te da la criatura |
| 🪙 +1 M Monedas / ✨ +1000 polvo | Para probar la tienda, las mejoras y la cría |
| 🐣 Criatura Épica / 🌈 Mítica | Añade una criatura a tu nido |
| ⏩ Abrir huevos ya | Termina la incubadora |
| 🌙 Noche de Saqueo on/off | Activa el evento en la ronda actual (o pon `Config.Testing.ForceLootNight = true` para todas) |
| 🌍 Llenar Huevo Comunitario | Llena la barra global en este servidor y reparte la criatura conmemorativa |
| 🏆 +3 robos en el ranking | Te suma 3 robos y refresca el cartel del lobby |

## Lista de comprobación por fase

Marca cada punto en una prueba con 4 jugadores (tú + 3 bots).

### Al entrar
- [ ] Aparece el HUD (barra, monedas, bolsa).
- [ ] Cada jugador tiene un nido asignado y la flecha del HUD lo señala.
- [ ] La ventana Output del servidor no muestra errores (si no activaste *API Services*, es normal un aviso de DataStore).

### Incubación
- [ ] Las brasas, luciérnagas y bloques de suerte se pueden recoger y reaparecen.
- [ ] La bolsa se llena y no pasa de su capacidad.
- [ ] Depositar en el huevo sube la barra y tu Afinidad.
- [ ] Los bots recogen y depositan solos (mira la barra subir).
- [ ] Empujar (F) a alguien con la bolsa llena le hace soltar Calor.
- [ ] Géiser: necesita dos jugadores pulsando a la vez.
- [ ] Con 🔥 Llenar la barra, salen los avisos de umbral y la fase termina antes.
- [ ] A mitad de la incubación empieza la **lluvia de brasas doradas**: las brasas se ponen doradas y dan el doble 25 s.
- [ ] Un jugador nuevo (primeras 5 rondas) no puede ser empujado; tampoco la misma persona dos veces en 30 s.

### Eclosión (10 s)
- [ ] El huevo tiembla y el foco salta entre los favoritos; **la cámara no se bloquea**.
- [ ] Con 7 o más jugadores salen **2 criaturas** (3 con 12 o más) y un foco para cada una, del color de su rareza.
- [ ] Un jugador que no se ha movido ni depositado en el último minuto no puede salir elegido (prueba a dejar a Player1 quieto con F8 desactivado).

### Persecución
- [ ] Cada elegido tiene 10 s de inmunidad y los demás 4 s de espera.
- [ ] **Robo por toque:** un toque de E junto al portador muestra "¡Robando! Quédate cerca…" y, si aguantas cerca 1,5 s, robas. Si el portador se aleja, sale "¡Se te ha escapado!".
- [ ] El portador ve "⚠️ ¡Te están robando! ¡Aléjate!" mientras alguien le hace el tira y afloja.
- [ ] **Escudos:** quien depositó 800 de Calor o más ve 🛡️ en la persecución. El primer robo que le hagan se bloquea y el escudo desaparece.
- [ ] Quien lleva una criatura no puede robar otra, y quien ya aseguró una no puede robar más en esa ronda.
- [ ] En su nido, robar cuesta más (2,25 s) y se ve la cuenta para asegurar.
- [ ] Tras un robo: 3 s de inmunidad y el que la pierde queda aturdido.
- [ ] Esprint (Shift), relevo (Q) y puerta del nido (R) funcionan; los bots usan esprint y puerta.
- [ ] Aguantar 30 s en tu nido asegura la criatura.
- [ ] **Zorros del bosque:** con menos de 6 jugadores salen zorros 🦊 del borde del mapa que van a por los portadores. Si te alcanzan, la criatura cae al suelo y cualquiera puede recogerla.
- [ ] Usa 🥚 Ser el portador para probar tú la huida.

### Prórroga
- [ ] Las criaturas que no están en un nido al acabar pasan a la prórroga (30 s): gana el primero que llegue a su nido.

### Resultados
- [ ] Cada ganador recibe su criatura en su nido (se ve en el nido y en el panel).
- [ ] Los demás reciben polvo de consolación; quien no hizo nada en la ronda ve "Sin consuelo".
- [ ] Los bots compran mejoras y huevos en la tienda del nido.

### Eventos
- [ ] 🌙 Noche de Saqueo: tras los resultados hay una fase "🌙 Saqueo" de 60 s con "Saquear" en las criaturas de nidos ajenos; unos bots saquean y otros vuelven a defender su nido.
- [ ] No se puede saquear si el dueño está dentro de su nido, ni una Secreta, ni dos veces en la misma ronda.
- [ ] El ladrón recibe una copia común; el dueño recibe un aviso y no pierde nada.
- [ ] 🌍 La barra del Huevo Comunitario (bajo el polvo) sube al depositar Calor.
- [ ] Al llenarla, quien aportó al menos 500 recibe la criatura del mes (la misma para todos).
- [ ] Huevo del Elegido: si el elegido pierde la criatura, aparece un huevo en su incubadora.

### Bandada e intercambio
- [ ] 🐦 Bandada: invita a un bot (lo acepta la mitad de las veces) y comprueba que se ve a través de las paredes.
- [ ] Al depositar, los miembros de la Bandada reciben un 10 % de Afinidad (mira la Afinidad del otro jugador).
- [ ] 🤝 Intercambio: pide uno a un bot. El bot ofrece su peor criatura, pulsa "Listo" y confirma cuando puede.
- [ ] Cambiar tu oferta quita el "Listo" de los dos. "Confirmar" solo se activa 3 s después de que los dos estén listos.
- [ ] Al completarse, las criaturas cambian de nido y aparece en "Últimos intercambios".
- [ ] Si alguien sale a mitad, el intercambio se cancela sin cambiar nada.

### Ranking y salón de la fama
- [ ] El cartel junto al claro del huevo muestra "Ladrones de la semana" y "Salón de la fama".
- [ ] Tras un robo en la persecución (o con 🏆 en F7), el ladrón aparece en el ranking en menos de un minuto.
- [ ] En la entrada de un nido ajeno aparece "Me gusta ❤" (G); en el tuyo, no deja.
- [ ] El mismo nido solo admite un "me gusta" tuyo por semana.

### Nido y datos
- [ ] Primera vez que entras (sin datos guardados): una criatura de regalo y un **huevo de bienvenida** que nace en 2 minutos.
- [ ] **Favoritas:** la ⭐ marca hasta 3. Una favorita no se puede liberar, y la primera te sigue flotando (también la ven los demás).
- [ ] Nueva generación (usa +1 M Monedas varias veces y cría hasta 40): las favoritas siguen en el nido.
- [ ] La tienda ya no vende el Escudo de Cáscara ni la Bolsa Grande; aparece la Estela de Brasas (estética).
- [ ] Panel del nido: criaturas, incubadora, mejoras, decorar, misiones y tienda.
- [ ] Liberar: una criatura seleccionada o "liberar guardadas" (pide confirmación; nunca toca las del nido).
- [ ] Decorar: comprar una pieza la coloca en el nido y suma Belleza al cartel.
- [ ] La producción suma monedas cada segundo.
- [ ] Con *API Services* activado: sal y vuelve a entrar y comprueba que se guardó todo.

## Si algo va mal

- **Un bot se queda quieto:** el piloto salta y descarta el objetivo tras 2,5 s atascado. Si sigue quieto, pulsa F8 dos veces en su ventana.
- **Errores del piloto:** salen en la Output del cliente con el prefijo `[Autopilot]`. No rompen el juego.
- **Quiero probar solo:** `Config.Round.MinPlayers` vale 1, así que puedes jugar en solitario con **Play** (F5), aunque sin robos.
