# The Egg Chooses: todo lo que falta para salir al mercado

Lista completa de lo que queda entre el prototipo actual y un juego publicado en Roblox: lo que hay que **programar**, lo que hay que **hacer en la web de Roblox (Creator Hub)**, el **arte y sonido**, y lo que tienes que **mirar y comprobar tú**.

Cada punto lleva quién lo hace y su prioridad:

| Marca | Quién |
|---|---|
| 🧑‍💻 | Programar (lo puedo hacer yo) |
| 👀 | Comprobar tú, jugando o en Roblox Studio |
| 🌐 | Configurar en el Creator Hub de Roblox (solo tú, con tu cuenta) |
| 🎨 | Arte, modelos, sonido o música (artista o tú con la Caja de herramientas) |
| 📣 | Marketing, comunidad o legal |

| Prioridad | Significado |
|---|---|
| **P0** | Bloquea el lanzamiento: sin esto no se puede publicar o se rompe algo |
| **P1** | Muy importante para que el juego funcione bien (retención, ingresos, quejas) |
| **P2** | Mejor tenerlo, pero se puede añadir después del lanzamiento |

Al final hay un **orden recomendado** por fases.

---

## 0. Arreglado ya en esta versión

- [x] Los laterales de los nidos del lobby se solapaban con los de al lado. Eran 24 nidos cuadrados de 36 studs (con el borde) en un círculo de 120 studs, y por la parte de dentro solo había ~27 studs entre uno y otro. Ahora `MapLayout.lobbyNestRadius()` aleja el círculo lo necesario (unos 178 studs) para que entre dos vecinos queden al menos `Config.Lobby.NestGap` (6 studs). Una prueba lo comprueba. 👀 Míralo en Studio: los caminos desde la plaza son ahora más largos.

---

## 1. Publicación y configuración en Roblox (Creator Hub)

Nada de esto se puede hacer desde el código: necesita tu cuenta.

- [ ] **P0 🌐 Crear la experiencia con dos lugares.** El lugar de inicio es el **lobby** y un segundo lugar es el de **partidas**. Publica el mismo `.rbxlx` en los dos. (Instrucciones al final de `docs/PRUEBAS.md`).
- [ ] **P0 🧑‍💻 Poner los PlaceId en `Config.Places`** (`Lobby` y `Match`). Mientras estén a 0, el juego funciona en modo combinado (todo en un servidor, como en Studio). Pásame los dos números y lo cambio.
- [ ] **P0 🌐 Tamaño de servidor del lobby: como mucho 24 jugadores.** Hay 24 nidos (`Config.Lobby.NestCount`). Si entra el jugador 25 no tiene nido: solo sale un aviso en la consola. Si quieres lobbies más grandes, dímelo y subo el número de nidos (o hago que el jugador 25 vaya a otro servidor).
- [ ] **P0 🌐 Tamaño de servidor de partidas: 12** (`Config.Matchmaking.MaxPlayers`). En la configuración del lugar de partidas.
- [ ] **P0 🌐 Activar "Enable Studio Access to API Services"** (para probar DataStores en Studio) y comprobar que los **DataStores** funcionan en el juego publicado.
- [ ] **P0 🌐 Activar los lugares para que se pueda teletransportar entre ellos** (en la misma experiencia funciona sin más; comprueba que el lugar de partidas no esté marcado como inaccesible para unirse directamente, o que, si lo está, `TeleportService` sí pueda llevar a él).
- [ ] **P0 🌐 Cuestionario de madurez del contenido** (Maturity & Compliance). Se rellena en el Creator Hub. El juego tiene robos (sin violencia), compras y objetos aleatorios de pago: contesta con sinceridad.
- [ ] **P0 🌐 Crear los game passes** y copiar sus IDs a `Config.GamePasses`: Nido VIP, x2 Monedas, Incubadora Rápida, Ranura de cría extra, Estela de Brasas.
- [ ] **P0 🌐 Crear los developer products** y copiar sus IDs a `Config.DevProducts`: Suerte del Lobby (`ServerLuck`), Huevo de Temporada, Repetir cría, packs de Monedas pequeño y grande.
- [ ] **P1 🌐 Crear la suscripción "Club del Nido"** y poner su ID (`EXP-...`) en `Config.ClubSubscriptionId`. Si no la creas, simplemente no aparece.
- [ ] **P1 🌐 Iconos e imágenes de cada pase y producto** (512×512). Sin imagen, la ventana de compra queda pobre.
- [ ] **P0 🌐 Página del juego:** nombre, descripción (en inglés y en español), icono (512×512), al menos 3 miniaturas (1920×1080), género, dispositivos (móvil, PC, tableta; consola solo si se prueba con mando).
- [ ] **P1 🌐 Vídeo para la página** (Roblox permite vídeos en las miniaturas). El momento de la eclosión y un robo en lo alto del parkour son lo más vistoso.
- [ ] **P1 🌐 Grupo de Roblox** para publicar la experiencia (mejor que la cuenta personal: permite colaboradores y reparto de ingresos).
- [ ] **P1 🌐 Servidores privados:** decidir si se venden y a qué precio (GDD 9.5). Ojo: en un servidor privado del lobby el emparejamiento necesita al menos 1 jugador y lanza con zorros.
- [ ] **P2 🌐 Notificaciones de la experiencia** (Experience Notifications) para avisar de la Luna de Sangre y la Noche de Saqueo a quien siga el juego.

## 2. Programación pendiente

### 2.1 Imprescindible antes de publicar (P0)

- [ ] **P0 🧑‍💻 Traducción al inglés.** Todo el texto del juego está escrito en español directamente en el código. La mayoría del público de Roblox no habla español. Hay que pasar los textos a tablas de localización (`LocalizationService`) y elegir el idioma según el del jugador. Es el trabajo de programación más grande que queda.
- [ ] **P0 🧑‍💻 Tutorial de la primera partida.** Un novato no sabe qué es el Calor, que hay que llevarlo al huevo ni cómo robar. Hacen falta flechas y avisos paso a paso: recoge una brasa, llévala al huevo, sube a un árbol, prueba la tirolina, roba (E). Sin esto, muchos se irán en el primer minuto.
- [ ] **P0 🧑‍💻 Seguridad del movimiento (anti-trampas).** En tirolinas, toboganes y setas trampolín el cliente mueve a su propio personaje. El servidor debería comprobar velocidades y saltos razonables y devolver a su sitio a quien se teletransporte o vuele. Es lo primero que prueban los tramposos.
- [ ] **P0 🧑‍💻 Límite de frecuencia en los remotos.** Ningún remoto limita cuántas veces por segundo se le puede llamar. Un tramposo podría saturar el servidor (por ejemplo, pidiendo compras de huevos o intercambios en bucle). Hay que poner un límite común (unas pocas llamadas por segundo por jugador).
- [ ] **P0 🧑‍💻 Quitar o arreglar la mejora Olfato.** Ahora se puede comprar pero no hace nada: eso son quejas y reembolsos. O la programo (marca en el mapa las fuentes de Calor más ricas, como dice el GDD) o la quito de la tienda.
- [ ] **P0 🧑‍💻 Comprobar `Config.Testing` antes de publicar.** Ya no se puede activar fuera de Studio (`Testing.enabled` mira `RunService:IsStudio()`), pero conviene dejar `TimeScale`, el piloto automático y las herramientas de depuración como estén y probar una ronda publicada con los tiempos reales (3 min 30 s de incubación, 2 min de persecución).
- [ ] **P0 🧑‍💻 Qué pasa si el lobby se llena** (jugador 25). Hoy no tiene nido. O se limita el servidor a 24 (ver sección 1) o se programa una solución.
- [ ] **P0 🧑‍💻 Copia de seguridad y versión de los datos.** `PlayerData.Version = 1` y el almacén `PlayerData_v1`. Antes de publicar hay que decidir cómo se migrarán los datos cuando cambie la estructura, y no cambiar `StoreName` después del lanzamiento (todos perderían su progreso).

### 2.2 Muy importante (P1)

- [ ] **P1 🧑‍💻 Emparejamiento por nivel.** Con la persecución actual, los que persiguen poco ganan muchas menos criaturas (en el simulador, un novato pasa de 0,34 a 0,10 victorias por hora). Que los novatos jueguen sus primeras partidas entre ellos.
- [ ] **P1 🧑‍💻 Botón de acción en móvil.** En móvil hay que pulsar los avisos (prompts) pequeños para recoger, depositar, robar o usar la tirolina. Un botón grande que haga "lo que toca" según dónde estés.
- [ ] **P1 👀 Controles en móvil y mando.** El portador ya tiene botones en pantalla de ⚡ Esprint y 🤝 Relevo (y Shift/Q o L3/L1 en mando). Empujar es un aviso (prompt) sobre el otro jugador. Comprueba que en un móvil se pulsan bien en plena carrera; si no, los hago más grandes o los muevo.
- [ ] **P1 🧑‍💻 Menú de ajustes:** volumen de música y efectos, sensibilidad, "Seguir jugando", ocultar las criaturas al hombro de los demás (rendimiento en móviles flojos).
- [ ] **P1 🧑‍💻 Tienda de la Plaza** (GDD 9.3): temas de nido, pedestales, accesorios para la criatura del hombro, emotes y títulos, con rotación diaria. Es la fuente principal de ingresos sin tocar la partida, y hoy no existe.
- [ ] **P1 🧑‍💻 Pase de temporada** (gratis + premium, solo estético) con misiones de jugar normal.
- [ ] **P1 🧑‍💻 Filtrado de texto** (`TextService:FilterStringAsync`) si se añade cualquier texto escrito por jugadores (renombrar criaturas, nombre del nido). Hoy no hay ninguno, pero el GDD propone "Renombrar criatura": sin filtro, Roblox lo prohíbe.
- [ ] **P1 🧑‍💻 Límites en los intercambios:** límite diario y que las Secretas no se puedan intercambiar los primeros días (contra el robo de cuentas y la reventa).
- [ ] **P1 🧑‍💻 Accesibilidad:** la rareza solo se distingue por el color. Añadir un icono o una letra (C, R, É, L, M, S) y una opción de tamaño de interfaz.
- [ ] **P1 🧑‍💻 Algo que hacer en el lobby mientras esperas** la cola (minijuego en la plaza o circuito de parkour con tiempo).
- [ ] **P1 🧑‍💻 Botón "Ver mi nido"** que lleve la cámara a tus gradas, y botón "Ir al nido de…" desde el ranking de "me gusta".
- [ ] **P1 🧑‍💻 Avisos al portador cuando un ladrón está cerca** (latido o vibración) y pistas para los ladrones entre señales (huellas o plumas que se desvanecen). Hacen la persecución más intensa (REVISION, puntos 1 y 2).
- [ ] **P1 🧑‍💻 Revisar el equilibrio de los huevos personales.** Un jugador muy activo abre cientos al mes y le quitan importancia a la persecución. Limitarlos y darle a la cría su propia ranura (REVISION 7).
- [ ] **P1 🧑‍💻 Inflación de rarezas:** demasiadas Épicas. La garantía de la barra solo para la primera criatura de la ronda (REVISION 8).
- [ ] **P1 🧑‍💻 Más analítica.** Hoy solo se registra el embudo del novato (`AnalyticsService`). Hacen falta también eventos de economía (Monedas y polvo que entran y salen), de partida (duración, robos, quién gana) y de tienda (qué se ve y qué se compra) para tomar decisiones con datos.
- [ ] **P1 🧑‍💻 Mensajes de error amables** si falla el teletransporte o el DataStore (ahora hay reintentos, pero el jugador debería ver qué pasa y poder volver a intentarlo).

### 2.3 Para después del lanzamiento (P2)

- [ ] **P2 🧑‍💻 Renombrar criaturas, fuegos artificiales, regalos, Dos al Hombro, Vitrina Grande** (GDD 9, ideas de monetización).
- [ ] **P2 🧑‍💻 Huevo del Admin:** evento en directo en todos los servidores (`MessagingService`).
- [ ] **P2 🧑‍💻 Visitar nidos de otros servidores** y títulos semanales para el campeón del ranking.
- [ ] **P2 🧑‍💻 Emotes de reacción** (con tu criatura al hombro).
- [ ] **P2 🧑‍💻 Desbloqueo progresivo de sistemas** (cría, intercambio, Bandada…) para no abrumar a los de 9-13 años.
- [ ] **P2 🧑‍💻 Mejoras igualadas en la partida** si se quiere cero influencia del pago (x2 Monedas adelanta bolsa y botas).
- [ ] **P2 🧑‍💻 Más eventos y temporadas:** criatura del mes, decoraciones de temporada, cambios en el mapa por estaciones.

## 3. Arte, modelos y sonido

- [ ] **P0 🎨 Mapa de la arena hecho a mano o retocado.** Ahora es geometría generada por código (bloques, cilindros): funciona, pero se ve "de prototipo". Lo ideal es un artista que lo construya en Studio con las mismas medidas (los árboles, alturas y puentes de `ArenaLayout`), y yo cambio el código para usar su mapa en vez de generarlo.
- [ ] **P0 🎨 Lobby y nidos con arte de verdad** (plaza, portal, carteles, nidos, decoraciones).
- [ ] **P1 🎨 Modelos de criatura de un artista.** El sistema ya admite modelos en `ReplicatedStorage/CreatureArt` (ver la galería de criaturas). Hacen falta los 12 cuerpos, las 12 cabezas y los efectos de patrón, aura y mutación.
- [ ] **P0 🎨 El huevo gigante** (modelo con grietas que se abren de verdad al eclosionar).
- [ ] **P1 🎨 Sonidos definitivos.** Ahora son los sonidos que trae Roblox con distinto tono. Elegir audios de la Caja de herramientas (los de Roblox se pueden usar) o encargarlos, y poner sus IDs en `src/shared/Sounds.luau`.
- [ ] **P1 🎨 Música:** una para el lobby, otra para la incubación, otra para la persecución (más tensa en los últimos 10 s). Solo audio con licencia (Roblox revisa los derechos).
- [ ] **P1 🎨 Interfaz con estilo propio:** iconos de Calor, Monedas, polvo, rarezas, botones; ahora son textos y emojis.
- [ ] **P1 🎨 Icono del juego y miniaturas** para la página (ver sección 1).
- [ ] **P2 🎨 Animaciones de las criaturas** (andar, saltar, celebrar) y del personaje al robar o al ser aturdido.

## 4. Lo que tienes que comprobar tú

### 4.1 En Roblox Studio (antes de publicar)

Usa la lista de comprobación de `docs/PRUEBAS.md`, sección por sección. Lo más importante:

- [ ] **P0 👀 Una ronda completa con 4 jugadores** (Prueba → Clientes y servidores → 4) sin errores en la ventana Output.
- [ ] **P0 👀 Los nidos del lobby ya no se solapan** (arreglado en esta versión) y nada flota ni parpadea.
- [ ] **P0 👀 Subir hasta arriba de cada tipo de árbol** (rampa y escalera) y usar todas las tirolinas y toboganes sin quedarse atascado.
- [ ] **P0 👀 Las brasas azules y moradas** salen en sus alturas y dan lo que dicen.
- [ ] **P0 👀 La criatura al hombro** se ve bien con distintos cuerpos (los grandes no deben tapar la cámara).
- [ ] **P0 👀 La revelación de la criatura en el huevo** se ve desde todo el claro.
- [ ] **P0 👀 Sonidos:** F7 → 🔊 Probar sonidos, y apunta los que sigan demasiado fuertes o flojos.
- [ ] **P1 👀 Equilibrio de la persecución:** ¿el elegido tiene opciones reales? ¿Hay suficientes robos? ¿Es divertido buscar entre señales? Las palancas están en `Config.Chase` y `Config.Shields`.
- [ ] **P1 👀 Que la barra se llene a buen ritmo** con 4, 8 y 12 jugadores (con las brasas nuevas puede llenarse antes).
- [ ] **P1 👀 Rendimiento:** en Studio, Ver → Estadísticas de rendimiento. Que no baje de 60 FPS en PC ni suba la memoria sin parar durante varias rondas.
- [ ] **P1 👀 Emulador de dispositivos de Studio** (móvil pequeño, tableta): que la interfaz quepa y los botones se puedan pulsar.

### 4.2 En el juego publicado (lo que Studio no puede probar)

- [ ] **P0 👀 Teletransporte real:** lobby → partida → lobby, con 2 o más cuentas. Que lleguen todos, que la Bandada vaya junta y que, al acabar, todos vuelvan con lo ganado.
- [ ] **P0 👀 Guardado entre lugares:** gana una criatura en la partida y comprueba que está en tu nido del lobby. Sal y vuelve a entrar.
- [ ] **P0 👀 Compras de verdad** con cada pase y producto. Primero ponles precio mínimo para probar y luego el precio real. Comprueba que se entregan, que no se entregan dos veces y que el pase sigue al volver a entrar.
- [ ] **P0 👀 Suerte del Lobby:** cómprala en el lobby y comprueba que sale la cuenta atrás y el anuncio con tu nombre.
- [ ] **P0 👀 Objetos aleatorios de pago** (Huevo de Temporada, Repetir cría): en países donde están restringidos (`PolicyService`) no deben aparecer. Pruébalo con una cuenta de esos países o con un amigo de allí.
- [ ] **P1 👀 Huevo Comunitario** (barra global entre servidores, `MemoryStore`) y **ranking semanal** (`OrderedDataStore`) con varios servidores abiertos a la vez.
- [ ] **P1 👀 Anuncios globales** de Míticas y Secretas en todos los servidores.
- [ ] **P1 👀 Móvil de verdad** (un Android barato y un iPhone): FPS, que se lea la interfaz, que se pueda robar y usar la tirolina con el dedo.
- [ ] **P1 👀 Con mala conexión:** que robar y el tira y afloja sigan funcionando con algo de retraso.
- [ ] **P1 👀 Eventos con horario:** Luna de Sangre (sábados 02:00, 12:00 y 20:00 UTC) y Noche de Saqueo (sábados y domingos 21-23 UTC). La página "Cómo se juega" tiene el calendario en tu hora.
- [ ] **P1 👀 Entrar a mitad de una partida** (un amigo te sigue) y salir a mitad: que no se rompa la ronda ni se pierdan cosas.

### 4.3 Prueba con gente (beta)

- [ ] **P0 👀 Beta cerrada con 10-20 personas** de la edad del público (9-13 años, con permiso de sus padres) durante una o dos semanas. Mira grabaciones de cómo juegan: dónde se pierden y dónde se aburren.
- [ ] **P1 👀 Medir** (con la analítica del Creator Hub): cuántos acaban la primera ronda, cuántos vuelven al día siguiente (D1) y a la semana (D7), cuánto dura una sesión, cuántos compran algo.
- [ ] **P1 👀 Comparar con el simulador:** robos por criatura, cuántas veces el elegido la conserva, victorias por hora de un novato.

## 5. Normas, legal y seguridad de los niños

- [ ] **P0 📣 Leer las normas de Roblox** (Community Standards y Terms of Use) y las de monetización: nada de "compra o pierdes", nada de temporizadores falsos, probabilidades visibles en lo aleatorio. El juego ya cumple lo que conozco, pero repásalo tú con la versión actual de las normas.
- [ ] **P0 📣 Objetos aleatorios de pago:** probabilidades a la vista antes de comprar (ya está hecho) y no ofrecerlos donde la ley lo prohíbe (ya está con `PolicyService`; comprobarlo, ver 4.2).
- [ ] **P0 📣 Nada de recoger datos personales** ni enlaces fuera de Roblox dentro del juego.
- [ ] **P1 📣 Intercambios:** una advertencia clara de que los intercambios son definitivos y de no aceptar tratos por cosas fuera del juego.
- [ ] **P1 📣 DevEx** (cambiar Robux por dinero): requisitos de edad, verificación de identidad, mínimo de Robux, datos fiscales. Revísalo en el Creator Hub antes de que empiecen a entrar Robux.
- [ ] **P2 📣 Integraciones de marca:** Roblox cobrará un porcentaje desde enero de 2027 (GDD 9.5).

## 6. Marketing y comunidad

- [ ] **P1 📣 Servidor de Discord o grupo de Roblox** para avisar de eventos y recoger fallos.
- [ ] **P1 📣 Plan de lanzamiento:** fecha, primer evento (por ejemplo, un fin de semana con Luna de Sangre), código o regalo para los primeros jugadores.
- [ ] **P1 📣 Anuncios patrocinados en Roblox** (Ads Manager) con un presupuesto pequeño de prueba: medir qué miniatura atrae más clics.
- [ ] **P1 📣 Creadores de contenido** (YouTube y TikTok de Roblox): el momento de la eclosión y los robos en lo alto del parkour son los clips. El botón 📸 Captura ya existe.
- [ ] **P2 📣 Calendario de actualizaciones** para los primeros 3 meses (cada semana o cada dos, algo nuevo: una criatura del mes, un tema de nido, un evento).

## 7. Después del lanzamiento (operación)

- [ ] **P1 👀 Revisar a diario la primera semana:** errores en la consola del servidor (Creator Hub → Analytics → Errors), compras fallidas, quejas.
- [ ] **P1 🧑‍💻 Herramienta de soporte:** poder mirar y corregir el perfil de un jugador (por ejemplo, devolverle una criatura perdida) sin tocar el DataStore a mano.
- [ ] **P1 🧑‍💻 Moderación:** poder expulsar o banear a tramposos (la `BanAPI` de Roblox) y registrar movimientos raros.
- [ ] **P2 👀 Pruebas A/B de precios** y del equilibrio con la analítica.

---

## Orden recomendado

1. **Ya (1-2 semanas):** probar en Studio con `docs/PRUEBAS.md` (sección 4.1). Crear los dos lugares, los pases y los productos (sección 1) y pasarme los IDs. Yo hago la seguridad (movimiento y límites de remotos), Olfato y el caso del lobby lleno.
2. **Después (2-4 semanas):** traducción al inglés, tutorial, botón de acción y controles de móvil, menú de ajustes. Encargar o elegir arte y sonido.
3. **Beta cerrada (1-2 semanas):** pruebas del juego publicado (sección 4.2) y con gente (4.3). Ajustar el equilibrio con lo que salga.
4. **Antes de abrir:** página del juego, icono, miniaturas, cuestionario de madurez, normas (sección 5).
5. **Lanzamiento** con un evento, y en las semanas siguientes la Tienda de la Plaza, el pase de temporada y el emparejamiento por nivel.
