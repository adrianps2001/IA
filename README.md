# The Egg Chooses (El Huevo Elige)

Juego social para Roblox: todo el servidor alimenta **un único huevo gigante**, el huevo **elige a un dueño** al eclosionar y los demás tienen 3 minutos para **robárselo**. Las criaturas que consigues viven en tu nido, producen Monedas aunque no estés y se pueden criar para obtener genes nuevos.

El diseño completo está en [`docs/GDD.md`](docs/GDD.md). La **guía visual del proyecto** (Roblox para creadores, archivos, Luau y todo el código explicado con demos interactivas) está en [`docs/index.html`](docs/index.html) y se publica con GitHub Pages en https://adrianps2001.github.io/IA/. El **informe del simulador de bots** (repetición de una partida y gráficas antes/después de los ajustes de equilibrio) está en [`docs/simulacion.html`](docs/simulacion.html). Este repositorio contiene el **prototipo jugable** (fase 1 del roadmap: una ronda completa en gris) junto con el nido, la cría, la economía, las misiones y la monetización.

## Cómo probarlo

1. Instala [Rokit](https://github.com/rojo-rbx/rokit) y ejecuta `rokit install` en la carpeta del repo (instala Rojo 7.4.4).
2. Elige una de estas dos opciones:
   - **Sincronizar en directo:** ejecuta `rojo serve`, abre Roblox Studio con el [plugin de Rojo](https://create.roblox.com/store/asset/13916111004) y pulsa *Connect*.
   - **Generar el archivo del juego:** ejecuta `rojo build -o TheEggChooses.rbxlx` y abre ese archivo en Studio.
3. En Studio, ve a **Test → Clients and Servers** y lanza **2 o más jugadores**. Hace falta más de uno para probar robos, géiseres y tratos.
4. (Opcional) Para que se guarden los datos en Studio, activa **Game Settings → Security → Enable Studio Access to API Services**. Si no lo activas, el juego funciona igual pero no guarda nada.

El mapa (bosque, huevo y 16 nidos) se genera por código al arrancar el servidor, así que no hace falta ningún archivo de mapa.

**Modo de prueba en Studio:** los jugadores Player2, Player3... juegan solos con un **piloto automático** (F8 lo activa o desactiva) y **F7** abre un panel de depuración (saltar fase, llenar la barra, ser el portador, dar monedas o criaturas). En Studio las fases duran el 35 % (`Config.Testing.TimeScale`). Nada de esto funciona fuera de Studio. La guía y la lista de comprobación están en [`docs/PRUEBAS.md`](docs/PRUEBAS.md).

## Cómo se juega una ronda (~12 min)

| Fase | Duración | Qué pasa |
|---|---|---|
| Preparados | 15 s | Se reinicia el huevo y la barra |
| Incubación | 8 min (o hasta llenar la barra) | Recoge **Calor** (brasas, luciérnagas del pantano, bloques de suerte, géiseres en pareja) y deposítalo en el huevo. Lo que depositas es tu **Afinidad**. Los objetos de ofrenda (cristal, pluma, hueso) sesgan los genes. Puedes empujar a quien lleve la bolsa llena (F). |
| Eclosión | 30 s | El huevo tiembla y un foco recorre a los jugadores como una ruleta. Probabilidad = Afinidad / total, con un **mínimo del 2 %** que sube un 2 % por cada ronda sin ser elegido (hasta un 12 %: "suerte acumulada"). |
| Persecución | 3 min (5 con Luna de Sangre) | El elegido lleva la criatura a su nido, con 10 s de inmunidad y 4 s de ventaja. Para robarla hay que mantener **E** 1,5 s junto al portador (2,25 s si está en su nido). Tras un robo hay 3 s de inmunidad y quien la pierde queda **aturdido** 2 s. Dentro de un nido ajeno se va al 60 % de velocidad. El portador tiene **esprint** (Shift), **relevo** a un aliado (Q) y **puerta del nido** 10 s (R). Aguantar **25 s seguidos** en tu nido **asegura** la criatura. |
| Prórroga | hasta 45 s | Si al acabar el tiempo el portador no está en su nido, gana el primero que meta la criatura en el suyo. |
| Resultados | 15 s | Se la queda quien la aseguró o la tenía en su nido. El resto recibe **Polvo de cáscara** de consuelo, y el elegido que la perdió, un **Huevo del Elegido**. |

**Tratos (T):** puedes ofrecer un trato a otro jugador. Si uno de los dos gana, el otro se lleva el 30 % de su polvo y una copia común de la criatura. Robarle a un aliado cuenta como traición y suma al título "Traidor".

## Estructura

```
default.project.json        Proyecto Rojo
src/shared/                 ReplicatedStorage.Shared (servidor y cliente)
  Config.luau               Todos los valores ajustables (tiempos, economía, precios, IDs)
  Rarity, Genes, Creature   Rarezas, catálogo de 60 genes, criaturas (lógica pura)
  Election, Economy,        La Elección, fórmulas de economía, misiones diarias,
  Quests, PlayerData        esquema de datos guardados (lógica pura, con tests)
  CreatureModel             Construye el modelo 3D modular de una criatura
  Decorations, DecorationModel  Decoraciones del nido: datos y construcción
  Remotes, RoundState       Remotos y estado de ronda replicado
  Events                    Horarios de eventos, reglas del saqueo, criatura comunitaria
  Testing                   Modo de prueba en Studio (Config.Testing)
src/server/                 ServerScriptService.Server
  Services/DataService      Guardado con bloqueo de sesión, autosave, vista para la UI
  Services/MapService       Mapa en gris: bosque circular, huevo y 16 nidos
  Services/RoundService     Máquina de fases de la ronda y reparto de premios
  Services/HeatService      Fuentes de Calor, bolsa, depósito, empujones, ofrendas
  Services/EggService       Barra del servidor, umbrales, tirada de la criatura
  Services/ChaseService     Portador, robo validado en servidor, relevo, tratos, esprint
  Services/NestService      Nido, producción por segundo, incubadora, cría, mejoras
  Services/QuestService     Misiones diarias y racha de 7 días
  Services/MonetizationService  Pases, productos, suscripción, recibos idempotentes
  Services/AnnouncementService  Avisos locales y globales (MessagingService)
  Services/CommunityService Huevo Comunitario (barra global en MemoryStore)
  Services/LootService      Noche de Saqueo
  Services/DebugService     Comandos de depuración (solo Studio)
src/client/                 StarterPlayerScripts.Client
  Controllers/HUDController     Bolsa, barra, temporizador, flecha de objetivo, avisos
  Controllers/HatchController   Espectáculo de eclosión y ruleta
  Controllers/ChaseController   Botones del portador y ventana de tratos
  Controllers/NestController    Panel del nido: criaturas (cría y liberar), incubadora, mejoras, decorar, misiones, tienda
  Controllers/EffectsController Latido del huevo y criaturas arcoíris
  Controllers/DebugController   Panel de depuración (F7, solo Studio)
  Controllers/AutopilotController Piloto automático para probar en Studio (F8)
  ChaseRules, Rewards,       Reglas de la persecución, reparto de premios y geometría
  MapLayout                 del mapa (lógica pura, compartida con el simulador)
sim/                        Simulador de bots: Round (una ronda), Meta (semanas), run (CLI)
tests/run.luau              Tests de la lógica pura
docs/GDD.md                 Documento de diseño
docs/index.html, assets/    Web de documentación (GitHub Pages)
docs/simulacion.html        Informe del simulador (lo genera tools/sim_report.py)
docs/PRUEBAS.md             Cómo probar en Studio y lista de comprobación
tools/                      export_data.luau, build_docs.py, sim_report.py, Json.luau
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
- **La criatura se escapaba en el ~80 % de las rondas** (robos en el último segundo). Se añadieron prórroga, asegurar, territorio, aturdimiento y ventaja del elegido. Ahora se escapa en menos del 2 %.
- **La barra se llenaba siempre a mitad de tiempo**, así que siempre salía Épica como mínimo. Nueva meta `base + por jugador`.
- **La economía estaba inflada unas 100 veces.** Curvas de precio más empinadas y producción sin conexión al 25 %.
- **Los novatos casi nunca eran elegidos.** Suerte acumulada.
- **Cientos de criaturas y Monedas sin uso a final de mes.** Liberar criaturas y decoración del nido.

Los detalles, con gráficas antes/después, están en `docs/simulacion.html`.

## La web de documentación

- **Publicarla:** en GitHub, *Settings → Pages → Build and deployment → Deploy from a branch*, rama `main`, carpeta `/docs`.
- **Actualizarla tras cambiar el código:** `python3 tools/build_docs.py`. Copia en `docs/index.html` los fragmentos de código (por nombre de función) y los datos reales del juego (vía `tools/export_data.luau`). Necesita `luau` en el PATH.
- **Verla en local:** `python3 -m http.server -d docs` y abrir http://localhost:8000.

## Antes de publicar

- **Monetización:** crea los game passes y developer products en el Creator Hub y pon sus IDs en `Config.GamePasses` y `Config.DevProducts`. Mientras valgan `0`, la tienda los muestra como "Pronto". Para el Club del Nido, rellena `Config.ClubSubscriptionId`.
- **Jugadores mínimos:** `Config.Round.MinPlayers` vale 1 para poder probar solo. En producción conviene 4 o más.

## Estado respecto al GDD

Implementado:
- Ronda completa con las 4 fases.
- Calor y sus 4 fuentes, bolsa limitada, empujones y ofrendas.
- Umbrales de la barra al 25/50/75/100 %.
- Elección con mínimo del 2 %.
- Persecución con robo, inmunidad, esprint, relevo, puerta del nido y Escudo de Cáscara, más las mecánicas añadidas con el simulador: prórroga, asegurar, territorio, aturdimiento y ventaja del elegido (configurables en `Config.Chase`).
- Tratos y traiciones, con títulos Leal/Traidor.
- Consuelo con Polvo de cáscara, y premio al elegido que pierde la criatura: polvo extra y un Huevo del Elegido (Rara a Épica).
- Nido con producción, también sin conexión (tope de 8 h).
- 60 genes, 6 rarezas y cría con mutación.
- Incubadora y huevos personales.
- Las 5 mejoras permanentes y la Nueva generación.
- Misiones diarias y racha de 7 días.
- Luna de Sangre, Noche de Saqueo (sábados y domingos, 21-23 UTC; por defecto el ladrón se lleva una copia común y el dueño no pierde nada) y Huevo Comunitario (barra global mensual en MemoryStore con criatura conmemorativa).
- Anuncios globales de Míticas y Secretas.
- Pases, productos y suscripción, con probabilidades públicas y comprobación de `PolicyService` para los objetos aleatorios de pago.
- Embudo de analítica.
- Ciclo visual de la ronda (atardecer, eclipse y noche).
- Liberar criaturas a cambio de polvo (una a una o las guardadas) y decoración del nido (12 piezas de Monedas o polvo, solo estéticas). Se pueden apagar con `Config.Sinks`.

Pendiente (siguientes fases del roadmap):
- Huevo Doble (requiere varias persecuciones a la vez) y Huevo del Admin.
- Grupos ("Bandada").
- Intercambio de criaturas.
- Visitas y "me gusta" en nidos, y salón de la fama.
- Ranking semanal de robos.
- Emotes de reacción.
- Selector de gen para la Ofrenda Dorada (el servidor ya la admite).
- Más sumideros de Monedas: pase de temporada y cosméticos.
- Emparejamiento por nivel (los novatos casi nunca ganan la persecución).
- Sonido.
- Tutorial guiado.
- Pase de temporada.
- Mapa artístico definitivo.
