# The Egg Chooses (El Huevo Elige)

Juego social para Roblox: todos los jugadores de una partida alimentan **un único huevo gigante**, el huevo **elige a un dueño** al eclosionar (con muchos jugadores, a varios: una criatura para cada uno) y los demás tienen 2 minutos para **robárselo** por un parkour de árboles gigantes: quien la tenga al acabar se la queda. Las criaturas que consigues se lucen en tu nido del **lobby**, producen Monedas aunque no estés y se pueden criar para obtener genes nuevos.

El diseño completo está en [`docs/GDD.md`](docs/GDD.md) (**versión 3**: la sección 13 explica qué se cambió tras la primera prueba y la 12, la versión 2). La **guía visual del proyecto** (Roblox para creadores, archivos, Luau y todo el código explicado con demos interactivas) está en [`docs/index.html`](docs/index.html) y se publica con GitHub Pages en https://adrianps2001.github.io/IA/. El **informe del simulador de bots** (repetición de una partida y gráficas que comparan la v2 y la v3 de las mecánicas) está en [`docs/simulacion.html`](docs/simulacion.html), la **galería de criaturas** (todas, construidas con el código del juego) en [`docs/criaturas.html`](docs/criaturas.html), y **cómo se juega**, sin código, mecánica a mecánica y con demos (una ronda en miniatura, el parkour en 3D, abrir huevos y calculadoras), en [`docs/juego.html`](docs/juego.html). Este repositorio contiene el **prototipo jugable** (fase 1 del roadmap: una ronda completa en gris) junto con el nido, la cría, la economía, las misiones y la monetización.

## Cómo probarlo

1. Instala [Rokit](https://github.com/rojo-rbx/rokit) y ejecuta `rokit install` en la carpeta del repo (instala Rojo 7.4.4).
2. Elige una de estas dos opciones:
   - **Sincronizar en directo:** ejecuta `rojo serve`, abre Roblox Studio con el [plugin de Rojo](https://create.roblox.com/store/asset/13916111004) y pulsa *Connect*.
   - **Generar el archivo del juego:** ejecuta `rojo build -o TheEggChooses.rbxlx` y abre ese archivo en Studio.
3. En Studio, pulsa **Jugar** (F5): apareces en tu nido del lobby; pulsa **⚔️ JUGAR** para ir a la arena (saldrán zorros como rivales). Para jugar con bots: pestaña **Prueba**, grupo **Clientes y servidores**, elige **Servidor local** y 4 jugadores (los detalles, en [`docs/PRUEBAS.md`](docs/PRUEBAS.md)).
4. (Opcional) Para que se guarden los datos en Studio, activa **Game Settings → Security → Enable Studio Access to API Services**. Si no lo activas, el juego funciona igual pero no guarda nada.

Los mapas (el lobby con 24 nidos y la arena con el huevo, 16 campamentos y el parkour) se generan por código al arrancar el servidor, así que no hace falta ningún archivo de mapa. En Studio el lobby y la arena están en el mismo servidor; para publicar los dos lugares, mira el final de [`docs/PRUEBAS.md`](docs/PRUEBAS.md).

**Último trabajo, decisiones a revisar y siguiente repaso de mejoras:** [`docs/REVISION.md`](docs/REVISION.md). **Todo lo que falta para salir al mercado** (programar, configurar en Roblox, arte y lo que hay que comprobar): [`docs/LANZAMIENTO.md`](docs/LANZAMIENTO.md).

**Modo de prueba en Studio:** los jugadores Player2, Player3... juegan solos con un **piloto automático** (F8 lo activa o desactiva) y **F7** abre un panel de depuración (jugar ya, saltar fase, llenar la barra, ser el portador, dar monedas o criaturas). En Studio las fases duran el 35 % (`Config.Testing.TimeScale`). Nada de esto funciona fuera de Studio. La guía y la lista de comprobación están en [`docs/PRUEBAS.md`](docs/PRUEBAS.md).

## Cómo se juega (GDD v3)

En el **lobby** está tu nido: tus criaturas en pedestales, la tienda, la incubadora, la cría, la decoración, los intercambios y la Bandada. Pulsa **⚔️ JUGAR** (o pisa el portal de la plaza): el emparejamiento te junta con otros (tu Bandada entra contigo) y viajáis a una partida de una ronda de ~6 min. Al acabar volvéis juntos al lobby.

| Fase | Duración | Qué pasa |
|---|---|---|
| Preparados | 6 s | Se reinicia el huevo y la barra |
| Incubación | 3,5 min (o hasta llenar la barra) | Recoge **Calor** (brasas, también en lo alto de los árboles; luciérnagas, cajas sorpresa, géiseres en pareja) y deposítalo en el huevo. Lo que depositas es tu **Afinidad**, y cada 800 te da un **escudo** para la persecución. A mitad hay una **lluvia de brasas doradas**. Las ofrendas (cristal, pluma, hueso) sesgan los genes. Puedes empujar a quien lleve la bolsa llena (F), salvo a los novatos y nunca a la misma persona seguida. |
| Eclosión | 10 s | Sale una criatura más por cada 5 perseguidores (hasta 3). Un foco salta entre los favoritos y se para en cada elegido. Probabilidad = Afinidad / total, con un **mínimo del 2 %** que sube un 2 % por cada ronda sin ser elegido (hasta un 12 %; un novato lo tiene desde su primera ronda). Solo pueden salir elegidos quienes han participado. |
| Persecución | 2 min (2 min 40 s con Luna de Sangre) | **Quien tenga la criatura al acabar se la queda.** El portador huye por el **parkour** (rampas, puentes, vigas, piedras, tirolinas, toboganes, setas trampolín, escondites) y solo se le ve a distancia cuando da la **señal**: cada 8 s durante 2 s, y todo el rato en los últimos 10 s. Para robar basta **un toque** (E) junto al portador: empieza un **tira y afloja** de 1,5 s que se rompe si se aleja. Cada **escudo** bloquea un robo (el elegido y los novatos empiezan con uno). Tras un robo hay 3 s de inmunidad y quien la pierde queda **aturdido** 2 s. Nadie lleva dos criaturas. El portador tiene **esprint** (Shift) y **relevo** a un aliado (Q). Con menos de 6 jugadores salen **zorros del bosque** que tiran la criatura al suelo. |
| Resultados | 8 s | Cada ganador se queda su criatura. El elegido que perdió la suya recibe un **Huevo del Elegido**; el resto, **Polvo de cáscara** si participó. |
| Saqueo | 60 s | Solo en la Noche de Saqueo (sábados y domingos, 21-23 UTC). |

**Tratos (T):** puedes ofrecer un trato a otro jugador. Si uno de los dos gana, el otro se lleva el 30 % de su polvo y una copia común de la criatura. Robarle a un aliado cuenta como traición y suma al título "Traidor".

## Estructura

```
default.project.json        Proyecto Rojo
src/shared/                 ReplicatedStorage.Shared (servidor y cliente)
  Config.luau               Todos los valores ajustables (tiempos, economía, precios, IDs)
  Rarity, Genes, Creature   Rarezas, catálogo de 64 genes, criaturas (lógica pura)
  Election, Economy,        La Elección, fórmulas de economía, misiones diarias,
  Quests, PlayerData        esquema de datos guardados (lógica pura, con tests)
  CreatureModel             Construye el modelo 3D de una criatura con el estilo elegido
  CreatureStyles/           Estilos de criatura: Chibi (monas, por defecto) y Classic
  ArenaLayout               Geometría del parkour de la arena (lógica pura, con tests)
  Place                     ¿Lobby, partida o los dos (Studio)?
  Navigator                 Caminar con PathfindingService (bots de prueba y zorros)
  Sounds                    Catálogo de sonidos
  Decorations, DecorationModel  Decoraciones del nido: datos y construcción
  Remotes, RoundState       Remotos y estado de ronda replicado
  Events                    Horarios de eventos, reglas del saqueo, criatura comunitaria
  Trade                     Máquina de estados del intercambio (doble confirmación)
  Leaderboard               Semanas, "me gusta" y top del ranking
  Testing                   Modo de prueba en Studio (Config.Testing)
src/server/                 ServerScriptService.Server
  Services/DataService      Guardado con bloqueo de sesión, autosave, vista para la UI
  Services/MapService       Mapas en gris: arena (huevo, campamentos, parkour) y lobby
  Services/MatchService     Quién juega la partida, llegadas, teletransportes y vuelta al lobby
  Services/MatchmakingService  Cola del lobby y lanzamiento de partidas
  Services/RoundService     Máquina de fases de la ronda y reparto de premios
  Services/HeatService      Fuentes de Calor, bolsa, depósito, empujones, ofrendas
  Services/EggService       Barra del servidor, umbrales, tirada de la criatura
  Services/ChaseService     Una persecución por criatura: tira y afloja, escudos, relevo, tratos
  Services/ForestService    Zorros del bosque en servidores de menos de 6
  Services/NestService      Nido, producción por segundo, incubadora, cría, mejoras
  Services/QuestService     Misiones diarias y racha de 7 días
  Services/MonetizationService  Pases, productos, suscripción, recibos idempotentes
  Services/AnnouncementService  Avisos locales y globales (MessagingService)
  Services/CommunityService Huevo Comunitario (barra global en MemoryStore)
  Services/LootService      Noche de Saqueo
  Services/PartyService     Bandadas
  Services/TradeService     Intercambio de criaturas
  Services/LeaderboardService  Ranking semanal, salón de la fama y cartel
  Services/DebugService     Comandos de depuración (solo Studio)
  Util/ArenaBuilder, LobbyBuilder, NestBuilder  Construyen el parkour, el lobby y los nidos
src/client/                 StarterPlayerScripts.Client
  Controllers/HUDController     Bolsa, barra, temporizador, flecha de objetivo, avisos
  Controllers/HatchController   Espectáculo de eclosión y ruleta
  Controllers/ChaseController   Botones del portador y ventana de tratos
  Controllers/NestController    Panel del nido: criaturas (cría, liberar, ⭐ favoritas), incubadora, mejoras, decorar, misiones, tienda
  Controllers/CosmeticsController  Criatura al hombro (eliges cuál con 🦜) y Estela de Brasas
  Controllers/EffectsController Latido del huevo, criaturas arcoíris y saltitos en los nidos
  Controllers/SoundController   Sonidos de las acciones
  Controllers/ArenaController   Setas trampolín, tirolinas y toboganes
  Controllers/SocialController  Bandada, intercambio e historial
  Controllers/DebugController   Panel de depuración (F7, solo Studio)
  Controllers/AutopilotController Piloto automático para probar en Studio (F8)
  ChaseRules, Rewards,       Reglas de la persecución, reparto de premios y geometría
  MapLayout                 del mapa (lógica pura, compartida con el simulador)
src/charsounds/             RbxCharacterSounds: pasos suaves (sustituye a los de Roblox)
sim/                        Simulador de bots: Round (una ronda), Meta (semanas), run (CLI)
tests/run.luau              Tests de la lógica pura
docs/GDD.md                 Documento de diseño
docs/index.html, assets/    Web de documentación (GitHub Pages)
docs/simulacion.html        Informe del simulador (lo genera tools/sim_report.py)
docs/criaturas.html         Galería de criaturas (la genera tools/build_creatures.py)
docs/juego.html             Cómo se juega, sin código (datos de tools/build_docs.py)
docs/PRUEBAS.md             Cómo probar en Studio y lista de comprobación
docs/REVISION.md            Resumen del último trabajo y decisiones a revisar
tools/                      export_data.luau, build_docs.py, sim_report.py, build_creatures.py,
                            RobloxMock.luau, Json.luau, sim_baseline_v2.json
```

**Seguridad:** el servidor es autoritativo. El cliente solo envía intenciones ("quiero esprintar"). El servidor valida distancias, tiempos de pulsación, costes y fases, y calcula todas las velocidades.

## Tests y comprobaciones

```sh
luau tests/run.luau                    # tests de rarezas, genes, Elección, economía, reglas, misiones y datos
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --flag:LuauSolverV2=true --sourcemap=sourcemap.json \
  --definitions=globalTypes.d.luau src  # análisis de tipos con las APIs de Roblox
```

La CI de GitHub (`.github/workflows/ci.yml`) ejecuta los tests, el análisis de tipos, comprueba que la web está al día y que el proyecto compila con Rojo en cada push.

## Simulador de bots (partidas de prueba)

Juega rondas completas y semanas de economía con bots de 6 personalidades (Novato, Casual, Recolector, Ladrón, Fiel y Con pases) sobre el mapa a escala real. Usa los **mismos módulos** que el juego.

```sh
luau --codegen sim/run.luau -a partida 7 12          # una partida narrada (semilla 7, 12 bots)
luau --codegen sim/run.luau -a lote 1 300 12         # 300 partidas y sus estadísticas
luau --codegen sim/run.luau -a lote 1 300 12 Chase.StealHoldTime=2   # probar otro valor de Config
luau --codegen sim/run.luau -a meta 7 30 60 > m.json # 30 días de economía con 60 bots
python3 tools/sim_report.py                          # regenera docs/simulacion.html (~4 min)
```

Con él se encontraron problemas serios de equilibrio, que ya están corregidos en `Config`:
- **La criatura se escapaba en el ~80 % de las rondas** (robos en el último segundo). Se añadieron prórroga, asegurar, territorio, aturdimiento y ventaja del elegido, y se escapaba en menos del 2 % (en la v3, al ganar quien la tenga al acabar, ya casi nunca se escapa).
- **La barra se llenaba siempre a mitad de tiempo**, así que siempre salía Épica como mínimo. Nueva meta `base + por jugador`.
- **La economía estaba inflada unas 100 veces.** Curvas de precio más empinadas y producción sin conexión al 25 %.
- **Los novatos casi nunca eran elegidos.** Suerte acumulada.
- **Cientos de criaturas y Monedas sin uso a final de mes.** Liberar criaturas y decoración del nido.

Y después, el repaso de diseño de la **versión 2** del GDD, medido con las mismas horas de juego:
- **La incubación casi no decidía nada** (el elegido conservaba la criatura el 10 % de las veces). Escudos de Afinidad y robo por toque: ahora ~1/3.
- **El premio era escaso**: 0,5 victorias por hora y el 76 % de las sesiones sin ganar nada. Con varias criaturas por ronda y rondas de 6 min, 2,3 victorias por hora y el 69 % de las sesiones con alguna.
- **Los novatos no ganaban nunca** (0 por hora en un mes). Ahora unas 0,35 por hora.

Y la **versión 3** (gana quien la tenga al acabar, parkour, señal): el simulador mostró que un portador más lento acababa siempre alcanzado, así que va a la misma velocidad que los demás, y que los que menos persiguen casi nunca conservaban la criatura, así que el elegido y los novatos empiezan con un escudo extra.

Los detalles, con gráficas que comparan la v2 y la v3, están en `docs/simulacion.html`.

## La web de documentación

- **Publicarla:** en GitHub, *Settings → Pages → Build and deployment → Deploy from a branch*, rama `main`, carpeta `/docs`.
- **Actualizarla tras cambiar el código:** `python3 tools/build_docs.py`. Copia en `docs/index.html` los fragmentos de código (por nombre de función) y los datos reales del juego (vía `tools/export_data.luau`). Necesita `luau` en el PATH.
- **Verla en local:** `python3 -m http.server -d docs` y abrir http://localhost:8000.

## Antes de publicar

- **Monetización:** crea los game passes y developer products en el Creator Hub y pon sus IDs en `Config.GamePasses` y `Config.DevProducts`. Mientras valgan `0`, la tienda los muestra como "Pronto". Para el Club del Nido, rellena `Config.ClubSubscriptionId`.
- **Jugadores mínimos:** `Config.Round.MinPlayers` vale 1 para poder probar solo. En producción conviene 4 o más.

## Estado respecto al GDD

Implementado:
- Lobby y partidas en lugares separados (GDD v3): cola con emparejamiento, Bandadas juntas, teletransporte a servidores reservados y vuelta al lobby; en Studio, todo en un servidor.
- Nido bonito en el lobby (pedestales con placa, valla, farolillos, cartel, cuenco con la incubadora) y campamento en la partida con tus 3 favoritas (GDD v3).
- Ronda completa con sus fases (incubación, eclosión, persecución, resultados y, en la Noche de Saqueo, saqueo).
- Arena con parkour de árboles gigantes: plataformas, rampas, escaleras, puentes, vigas, piedras flotantes, tirolinas, toboganes, setas trampolín y escondites (GDD v3).
- Criaturas con estilo chibi intercambiable y soporte para modelos de artista (GDD v3).
- Sonidos para las acciones y pasos suaves (GDD v3).
- Calor y sus 4 fuentes, bolsa limitada, empujones y ofrendas.
- Umbrales de la barra al 25/50/75/100 %.
- Elección con mínimo del 2 %, suerte acumulada, novatos al 12 % en su primera ronda y sin inactivos (GDD v2).
- Varias criaturas por ronda (1 a 3 según los jugadores; sustituye al Huevo Doble), rondas de ~6 min, eclosión de 10 s y lluvia de brasas doradas (GDD v2).
- Persecución por criatura (GDD v3: gana quien la tenga al acabar) con señal del portador, robo por toque (tira y afloja), escudos de Afinidad y extra para elegidos y novatos, inmunidad, esprint, relevo, aturdimiento, ventaja de los elegidos y zorros del bosque en partidas pequeñas (configurable en `Config.Chase`, `Config.Shields` y `Config.ForestThieves`).
- Sin pago por ganar: los escudos se ganan depositando Calor y la Bolsa Grande pasa a ser la Estela de Brasas (estética).
- Favoritas que sobreviven a la Nueva generación, criatura al hombro (en el lobby y en la partida), huevo de bienvenida y protección de novatos contra empujones.
- Brasas por niveles en el parkour: azules (×2) desde la mitad de los árboles y moradas (×4) en la cima (GDD v3.1).
- La criatura sale del huevo en el centro del claro durante la eclosión (GDD v3.1).
- Sonidos con volumen equilibrado por grupos y botón para probarlos todos (F7).
- Anti-trampas: el servidor comprueba el movimiento (tirolinas, setas…) y limita cuántas veces por segundo se puede llamar a cada remoto (`Config.AntiCheat`).
- Botón de acción en móvil, analítica de economía y de partida, comandos de soporte y moderación (`!ayuda`, solo administradores) y 🏡 Visitar nidos.
- Tutorial de la primera partida, pistas de la persecución (aviso de ladrón cerca y huellas), ajustes ⚙️ guardados en el perfil y botón 👀 Mi nido.
- Intercambios con tope diario y Secretas bloqueadas sus 3 primeros días; precios redondos; lobby decorado por código (terreno, bosque, flores, farolillos, bancos).
- Tratos y traiciones, con títulos Leal/Traidor.
- Bandada (grupos de hasta 4: reparten el 10 % del Calor, se ven a través de las paredes y +10 % de polvo con un amigo) e intercambio de criaturas con doble confirmación, cambio atómico e historial.
- Consuelo con Polvo de cáscara, y premio al elegido que pierde la criatura: polvo extra y un Huevo del Elegido (Rara a Épica).
- Nido con producción, también sin conexión (tope de 8 h).
- 64 genes (12 por ranura más un Secreto en cada una: Fénix, Unicornio, Aurora, Agujero Negro y Arcoíris Eterno), 6 rarezas y cría con mutación.
- Incubadora y huevos personales.
- Las 4 mejoras permanentes (bolsa, botas, nido e incubadora) y la Nueva generación.
- Misiones diarias y racha de 7 días.
- Luna de Sangre (3 franjas los sábados), Noche de Saqueo (sábados y domingos, 21-23 UTC, en una fase propia tras los resultados; por defecto el ladrón se lleva una copia común y el dueño no pierde nada) y Huevo Comunitario (barra global mensual en MemoryStore con criatura conmemorativa).
- Anuncios globales de Míticas y Secretas.
- Pases, productos y suscripción centrados en el lobby (nada de pago toca la partida; GDD 9 v3.1), con probabilidades públicas y comprobación de `PolicyService` para los objetos aleatorios de pago.
- Ranking semanal de robos y salón de la fama (nidos con más "me gusta"), en un cartel de la plaza del lobby, con un OrderedDataStore por semana.
- Embudo de analítica.
- Ciclo visual de la ronda (atardecer, eclipse y noche).
- Liberar criaturas a cambio de polvo (una a una o las guardadas) y decoración del nido (12 piezas de Monedas o polvo, solo estéticas). Se pueden apagar con `Config.Sinks`.

Pendiente (siguientes fases del roadmap):
- Huevo del Admin (evento en directo).
- Visitar nidos de otros servidores y títulos semanales para el campeón.
- Emotes de reacción.
- Tienda de la Plaza (temas de nido, pedestales, accesorios para la criatura del hombro), renombrar criaturas, fuegos artificiales y regalos (GDD 9, v3.1).
- Más sumideros de Monedas: pase de temporada y cosméticos.
- Emparejamiento por nivel: con la persecución v3, los que menos persiguen ganan bastante menos (ver `docs/REVISION.md`).
- Sonidos definitivos (ahora se usan los que trae Roblox) y música.
- Tutorial guiado.
- Pase de temporada.
- Mapas artísticos definitivos (lobby y arena) y modelos de criatura hechos por un artista.
