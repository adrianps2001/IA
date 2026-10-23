# GDD v3: qué se ha cambiado, qué revisar y qué falta

Este documento resume la **versión 3**, que sale de tu primera prueba del juego, y lo que conviene revisar. El GDD está en [`GDD.md`](GDD.md): la sección 13 explica cada cambio y las secciones marcadas **(v3)**, los detalles. Los cambios de la v2 siguen en la sección 12.

## Lo que pediste y cómo ha quedado

| Tu nota | Qué se ha hecho |
|---|---|
| No se pueden enseñar las criaturas | **Nido del lobby** con 12 pedestales en gradas: placa con nombre, rareza y producción, aro del color de la rareza (dorado las favoritas), foco en las Legendarias o mejores y saltitos. Valla, farolillos, arco con tu cartel y cuenco con la incubadora, que brilla cuando hay huevos listos. En la partida, tu campamento muestra tus 3 favoritas. |
| Pasos chirriantes | Sustituidos por pasos propios: un golpecito suave por zancada, distinto en hierba y madera. |
| Más sonidos | Catálogo [`src/shared/Sounds.luau`](../src/shared/Sounds.luau) con unos 35 sonidos: Calor (con combo), depósito, bolsa llena, cajas sorpresa, empujones, géiseres, latido del huevo, eclosión, portador, tira y afloja, robos, escudos, señal, cuenta atrás, trampolines, tirolinas, compras, cola y clics. |
| Lobby antes de las partidas | **Lugar aparte** con más jugadores, tu nido y todo lo del nido (tienda, mejoras, cría, liberar, decorar, intercambios, Bandada). Cola con emparejamiento, teletransporte a una partida y vuelta al lobby. En la partida apareces con tu campamento. |
| La criatura es fea | **Estilo chibi** (ojos grandes con brillo, mofletes, boquita "ω", barriguita, patitas) y un rasgo por gen. Míralas en [`criaturas.html`](criaturas.html). Se cambia de estilo en `Config.Creatures.Style` y se pueden usar modelos de un artista sin tocar código (ver la galería). |
| Bots atascados en paredes | Bots y zorros con **PathfindingService** (`Navigator`): rodean, suben rampas y, si no avanzan, saltan, se apartan y buscan otro camino. |
| Las cajas sorpresa no desaparecen | Se ocultaba la caja, pero no los "?" de sus caras. Ahora se apaga todo, y con la bolsa llena sale un aviso. |
| Quedarte la criatura al acabar, parkour, sin llevarla al nido | **Gana quien la tenga al acabar.** Parkour de 12 árboles gigantes con rampas, escaleras, puentes, vigas, piedras flotantes, tirolinas, toboganes, setas trampolín y escondites. Caer no tiene castigo. **Señal** del portador cada 8 s y en los últimos 10 s. |

## Resultado, medido con el simulador

Mismas semillas y horas de juego que la v2 (30 días, 60 jugadores; 12 jugadores para la persecución). Las gráficas están en [`simulacion.html`](simulacion.html).

| | v2 | v3 |
|---|---|---|
| Duración de la ronda (la v3 incluye ~35 s de cola y viajes) | 6,0 min | 6,5 min |
| Victorias por hora de juego | 2,29 | 2,14 |
| Sesiones con alguna victoria | 71 % | 62 % |
| El elegido conserva su criatura | 36 % | 30 % |
| Robos por criatura | 3,5 | 2,9 |
| La criatura cambia de manos en los últimos 10 s | — | 28 % |
| Novato: victorias por hora | 0,34 | 0,10 |
| Casual: victorias por hora | 1,02 | 0,17 |
| Ladrón: victorias por hora | 3,47 | 3,73 |

**Nada de esto se ha probado aún dentro de Roblox Studio.** Todo pasa los 46 tests, el análisis de tipos y la compilación, y el simulador juega con las mismas reglas. Pero el lobby, la cola, el parkour, las tirolinas, los sonidos y las criaturas nuevas hay que verlos en Studio con [`PRUEBAS.md`](PRUEBAS.md).

## Decisiones que debes revisar

1. **El punto débil: los que persiguen poco ganan mucho menos.** Sin nido donde asegurar, gana quien recupera la criatura al final, y esos son los que más persiguen. Ya están puestos un escudo extra para el elegido y otro para los novatos (`Config.Shields.ChosenBonus` y `NewPlayerBonus`). El simulador no imita el parkour, que debería ayudar al portador, así que puede que jugando sea mejor. Si se confirma, hay más palancas:
   - `Chase.CarrierMaxBoots = true`: el portador corre como con las botas al máximo.
   - Más escudos de bonus o persecución de 90 s. Con todo junto, novatos y casuales llegan a ~0,3 victorias por hora, pero queda menos de un robo por criatura (aburrido).
   - Emparejamiento por nivel (novatos con novatos).
2. **La señal: cada 8 s, 2 s visible, y los últimos 10 s siempre** (`Config.Chase.RevealEvery`, `RevealSeconds`, `FinalRevealSeconds`). Es la decisión que más cambia la sensación de la persecución: con señales más espaciadas hay más escondite y más búsqueda.
3. **El portador va a la misma velocidad que los demás** (`Chase.CarrierSpeedMultiplier = 1`; en la v2 era 0,9). Más lento, le alcanzaban siempre.
4. **Una ronda por partida** (`Config.Matchmaking.RoundsPerMatch = 1`) y vuelta al lobby. Cada viaje cuesta unos segundos de carga. Si se hace pesado, 2 o 3 rondas por partida.
5. **Cuándo sale una partida:** con 8 jugadores enseguida, con 4 tras 20 s, con los que haya tras 45 s (`Config.Matchmaking`). Partidas de 12 como mucho.
6. **"Seguir jugando" activado por defecto:** al volver al lobby vuelves solo a la cola a los 3 s. Así se juega seguido, pero quizá quieras que por defecto te quedes en el lobby a ver tu nido.
7. **El parkour sale siempre igual** (semilla `Config.Arena.Seed`). Con otra semilla cambian los bloques flotantes y los arbustos; los árboles y los puentes son fijos. Es un prototipo: un mapa hecho a mano en Studio sería mejor.
8. **Sonidos provisionales:** usan los que trae Roblox con distintos tonos (funcionan sin subir nada). Habría que elegir audios mejores de la Caja de herramientas y poner sus ID en `Sounds.luau`.
9. ~~**Suerte del Servidor y Ofrenda Dorada**~~ **(resuelto en la v3.1):** con lugares separados no funcionaban (se compraban en el lobby y no llegaban a la partida). La Suerte pasa a ser **Suerte del Lobby** (huevos del nido de todo el lobby) y la Ofrenda Dorada y el Auto-Depósito se retiran: nada de pago toca la partida (GDD 9).
10. **Brasas por niveles (v3.1):** azules ×2 desde la mitad de los árboles (`Config.Heat.BlueEmber`, 24) y moradas ×4 en la cima (`Config.Heat.PurpleEmber`, 10). El simulador no las tiene en cuenta (sus bots no suben). Si en las pruebas la barra se llena demasiado pronto, bajar su número antes que su valor.
11. **Volumen de los sonidos (v3.1):** se ha estimado lo fuerte que suena cada archivo (`Sounds.Gain`). Con F7 → 🔊 Probar sonidos se oyen todos seguidos con su volumen; si alguno sigue mal, se cambia su `Level`.

Decisiones de la v2 que siguen abiertas: la meta del Huevo Comunitario (25 millones al mes), que la Bandada no dé alianza automática y que se puedan intercambiar Secretas.

## Para publicar el juego con lobby

1. En el Creator Hub, crea un segundo lugar en tu experiencia: el de inicio será el lobby y el nuevo, el de las partidas.
2. Publica el mismo archivo en los dos y pon sus `PlaceId` en `Config.Places`.
3. Lobby con más jugadores por servidor (por ejemplo, 30); partidas con 12.

Mientras `Config.Places` esté a 0, todo funciona en un solo servidor (como en Studio).

---

## Qué más se podría mejorar

Lo nuevo que ha salido con la v3, y lo pendiente de antes que sigue importando.

### De la v3

1. **Que el portador se sienta perseguido y no solo, a ratos, visto.** Un sonido de "corazón" o vibración cuando un ladrón está cerca (a menos de 20 studs) le diría al portador que huya, y a los ladrones que van bien.
2. **Ayudas para encontrar al portador sin señal.** Huellas brillantes que se desvanecen o plumas que suelta la criatura al correr: dan algo que seguir entre señales sin delatarlo del todo.
3. **El lobby necesita algo que hacer mientras esperas.** Un minijuego en la plaza (recoger brasas sueltas o un circuito de parkour corto con tiempo) haría la espera divertida y enseñaría a moverse por el parkour.
4. **Tutorial del parkour.** La primera partida de un novato podría tener flechas en el suelo hacia la rampa más cercana y un cartel "pulsa E en el poste para la tirolina".
5. **Galería del nido en el móvil.** Las placas se leen de cerca. Un botón "Ver mi nido" en el panel que mueva la cámara a las gradas lo haría lucir más.
6. **Visitar nidos ajenos.** Ahora el lobby tiene muchos nidos juntos: un botón "Ir al nido de…" en el ranking de "me gusta" convierte el salón de la fama en algo que se visita.

### De antes (siguen pendientes)

7. **Los huevos personales eclipsan a la persecución.** Un jugador muy activo abre cientos de huevos al mes. Limitar los huevos personales y dar a la cría una ranura propia.
8. **Inflación de rarezas.** Muchas Épicas: la garantía de la barra solo para la primera criatura de la ronda y Rara desde el 50 %.
9. **La Afinidad da doble ventaja** (Elección y escudos): rendimientos decrecientes.
10. **Demasiados sistemas para 9-13 años:** desbloqueo progresivo.
11. **Botón de acción contextual en móvil** (recoger / depositar / robar / tirolina).
12. **Seguridad de movimiento:** ahora el cliente mueve al personaje en tirolinas y trampolines; el servidor debería comprobar velocidades razonables (y registrar teletransportes raros) antes de abrir el juego.
13. **Intercambio y dinero real:** límites diarios y Secretas intransferibles los primeros días.
14. **Ingresos sin pago por ganar:** diseñado en la v3.1 (GDD 9: Tienda de la Plaza con temas de nido, pedestales y accesorios para la criatura del hombro; renombrar criaturas; fuegos artificiales; regalos). Falta hacerlo. Y decidir si x2 Monedas debe dejar de acelerar las mejoras de bolsa y botas (lo único de pago que apenas toca la partida).
15. **Accesibilidad:** la rareza se distingue por color; añadir icono y un ajuste de tamaño de interfaz.
16. **Medir en la beta** lo que predice el simulador (victorias por sesión, robos por criatura, el elegido conserva, tiempo en la cola).

### Lo primero, siempre

17. **Probar en Studio** con [`PRUEBAS.md`](PRUEBAS.md): tú solo con los zorros (F5 → Jugar) y con 4 jugadores.
