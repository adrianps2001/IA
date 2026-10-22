# The Egg Chooses (El Huevo Elige)

Juego social para Roblox: todo el servidor alimenta **un único huevo gigante**, el huevo **elige a un dueño** al eclosionar y los demás tienen 3 minutos para **robárselo**. Las criaturas que consigues viven en tu nido, producen Monedas aunque no estés y se pueden criar para obtener genes nuevos.

El diseño completo está en [`docs/GDD.md`](docs/GDD.md). La **guía visual del proyecto** (Roblox para creadores, archivos, Luau y todo el código explicado con demos interactivas) está en [`docs/index.html`](docs/index.html) y se publica con GitHub Pages en https://adrianps2001.github.io/IA/. Este repositorio contiene el **prototipo jugable** (fase 1 del roadmap: una ronda completa en gris) junto con el nido, la cría, la economía, las misiones y la monetización.

## Cómo probarlo

1. Instala [Rokit](https://github.com/rojo-rbx/rokit) y ejecuta `rokit install` en la carpeta del repo (instala Rojo 7.4.4).
2. Elige una de estas dos opciones:
   - **Sincronizar en directo:** ejecuta `rojo serve`, abre Roblox Studio con el [plugin de Rojo](https://create.roblox.com/store/asset/13916111004) y pulsa *Connect*.
   - **Generar el archivo del juego:** ejecuta `rojo build -o TheEggChooses.rbxlx` y abre ese archivo en Studio.
3. En Studio, ve a **Test → Clients and Servers** y lanza **2 o más jugadores**. Hace falta más de uno para probar robos, géiseres y tratos.
4. (Opcional) Para que se guarden los datos en Studio, activa **Game Settings → Security → Enable Studio Access to API Services**. Si no lo activas, el juego funciona igual pero no guarda nada.

El mapa (bosque, huevo y 16 nidos) se genera por código al arrancar el servidor, así que no hace falta ningún archivo de mapa.

## Cómo se juega una ronda (~12 min)

| Fase | Duración | Qué pasa |
|---|---|---|
| Preparados | 15 s | Se reinicia el huevo y la barra |
| Incubación | 8 min (o hasta llenar la barra) | Recoge **Calor** (brasas, luciérnagas del pantano, bloques de suerte, géiseres en pareja) y deposítalo en el huevo. Lo que depositas es tu **Afinidad**. Los objetos de ofrenda (cristal, pluma, hueso) sesgan los genes. Puedes empujar a quien lleve la bolsa llena (F). |
| Eclosión | 30 s | El huevo tiembla y un foco recorre a los jugadores como una ruleta. Probabilidad = Afinidad / total, con un **mínimo del 2 %** para todos. |
| Persecución | 3 min (5 con Luna de Sangre) | El elegido lleva la criatura a su nido. Para robarla hay que mantener **E** 1,5 s junto al portador. Hay 3 s de inmunidad tras cada robo. El portador tiene **esprint** (Shift), **relevo** a un aliado (Q) y **puerta del nido** 10 s (R). |
| Resultados | 15 s | Quien tenga la criatura **dentro de su nido** al acabar el tiempo se la queda. El resto recibe **Polvo de cáscara** de consuelo. |

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
  Remotes, RoundState       Remotos y estado de ronda replicado
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
src/client/                 StarterPlayerScripts.Client
  Controllers/HUDController     Bolsa, barra, temporizador, flecha de objetivo, avisos
  Controllers/HatchController   Espectáculo de eclosión y ruleta
  Controllers/ChaseController   Botones del portador y ventana de tratos
  Controllers/NestController    Panel del nido: criaturas, incubadora, mejoras, misiones, tienda
  Controllers/EffectsController Latido del huevo y criaturas arcoíris
tests/run.luau              Tests de la lógica pura
docs/GDD.md                 Documento de diseño
docs/index.html, assets/    Web de documentación (GitHub Pages)
tools/                      export_data.luau y build_docs.py: generan la web desde el código
```

**Seguridad:** el servidor es autoritativo. El cliente solo envía intenciones ("quiero esprintar"). El servidor valida distancias, tiempos de pulsación, costes y fases, y calcula todas las velocidades.

## Tests y comprobaciones

```sh
luau tests/run.luau                    # 27 tests de rarezas, genes, Elección, economía, misiones y datos
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --flag:LuauSolverV2=true --sourcemap=sourcemap.json \
  --definitions=globalTypes.d.luau src  # análisis de tipos con las APIs de Roblox
```

La CI de GitHub (`.github/workflows/ci.yml`) ejecuta los tests, el análisis de tipos, comprueba que la web está al día y que el proyecto compila con Rojo en cada push.

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
- Persecución con robo, inmunidad, esprint, relevo, puerta del nido y Escudo de Cáscara.
- Tratos y traiciones, con títulos Leal/Traidor.
- Consuelo con Polvo de cáscara.
- Nido con producción, también sin conexión (tope de 8 h).
- 60 genes, 6 rarezas y cría con mutación.
- Incubadora y huevos personales.
- Las 5 mejoras permanentes y la Nueva generación.
- Misiones diarias y racha de 7 días.
- Luna de Sangre.
- Anuncios globales de Míticas y Secretas.
- Pases, productos y suscripción, con probabilidades públicas.
- Embudo de analítica.
- Ciclo visual de la ronda (atardecer, eclipse y noche).

Pendiente (siguientes fases del roadmap):
- Huevo Doble, Noche de Saqueo, Huevo del Admin y Huevo Comunitario.
- Grupos ("Bandada").
- Intercambio de criaturas.
- Visitas y "me gusta" en nidos, y salón de la fama.
- Ranking semanal de robos.
- Emotes de reacción.
- Selector de gen para la Ofrenda Dorada (el servidor ya la admite).
- Sonido.
- Tutorial guiado.
- Pase de temporada.
- Mapa artístico definitivo.
