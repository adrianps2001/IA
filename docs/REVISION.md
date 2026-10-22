# Trabajo de la noche: qué se hizo y qué debes revisar

Seis bloques, cada uno en su propio commit en la rama `claude/the-egg-chooses` (PR #2). En cada bloque se pasaron los tests, el análisis de tipos y `rojo build`, se comprobó el simulador y se actualizaron la web y el README. **No se ha fusionado ni publicado nada.**

| # | Bloque | Commit |
|---|---|---|
| 1 | Modo de prueba en Studio: piloto automático (F8), panel de depuración (F7) y lista de comprobación | `f8c7ade` |
| 2 | Liberar criaturas a cambio de polvo y decoración del nido | `ca14269` |
| 3 | Premio al elegido que pierde: Huevo del Elegido | `1b90bde` |
| 4 | Eventos: Noche de Saqueo y Huevo Comunitario (Huevo Doble, pendiente) | `4356973` |
| 5 | Bandada e intercambio seguro | `6b6e12b` |
| 6 | Ranking semanal de robos y salón de la fama | `b387800` |

Tests: de 33 a 41, todos correctos. Análisis de tipos: sin errores.

## ⚠️ Lo más importante

**Nada de esto se ha ejecutado dentro de Roblox.** Aquí no se puede abrir Studio. Todo está comprobado con tests de la lógica pura, el análisis de tipos con las APIs de Roblox, la compilación con Rojo y el simulador. Pero la interfaz nueva (pestaña Decorar, panel de la Bandada, ventana de intercambio, cartel del ranking), los prompts y los DataStores necesitan una prueba real. Para eso está el bloque 1: sigue [`docs/PRUEBAS.md`](PRUEBAS.md) con 4 jugadores en *Test → Clients and Servers*.

## Decisiones que debes revisar

Todas se pueden cambiar en `src/shared/Config.luau` sin tocar código.

### 1. Modo de prueba
- **En Studio las fases duran el 35 %** (`Config.Testing.TimeScale = 0.35`), también cuando pulsas *Play* tú solo. Pon `1` si quieres los tiempos reales. Fuera de Studio no tiene ningún efecto.
- Los jugadores de prueba Player2, Player3… empiezan en piloto automático; tú (Player1), no.

### 2. Liberar y decorar
- **Polvo por liberar:** Común 2, Rara 8, Épica 30, Legendaria 120, Mítica 500. **Las Secretas no se pueden liberar.**
- "Liberar guardadas" solo toca Comunes que no producen y nunca deja menos de 40 criaturas (lo que pide la Nueva generación).
- **Decoración:** 12 piezas. 8 se pagan con Monedas (de 25 mil a 500 millones) y 4 con polvo (de 400 a 15 000). Son solo estéticas, no colisionan y **se conservan en la Nueva generación**.
- Efecto en el simulador (30 días): el máximo de criaturas por jugador baja de 265 a ~110 y el polvo sobrante del Grinder, un 35 %. Las Nuevas generaciones bajan un poco (generación media 0,61 → 0,56), porque los bots gastan en decoración. El ritmo de compra de los bots (decorar solo si cuesta ≤ ¼ de lo que están dispuestos a gastar) es una suposición.
- `Config.Sinks` apaga cualquiera de los dos.

### 3. Huevo del Elegido
- Si el elegido no se queda la criatura (se la roban o escapa), recibe +50 de polvo y un huevo Rara–Épica. Entra aunque la incubadora esté llena.
- En el simulador, un novato recibe unos 4 al mes. No cambia quién gana la persecución; solo hace que ser elegido nunca sea una pérdida.

### 4. Eventos
- **Noche de Saqueo:** sábados y domingos de 21:00 a 23:00 UTC (23:00-01:00 en España en horario de verano), solo durante la Incubación.
  - **Versión prudente por defecto (`OwnerLoses = false`):** el dueño no pierde nada y el ladrón se lleva una copia común. Si quieres el saqueo "de verdad" del GDD (la criatura cambia de dueño), pon `true`. Las Secretas son inmunes siempre.
  - Las reglas: el dueño dentro de su nido lo protege, 1 saqueo por jugador y ronda, el nido queda protegido 90 s y hay que mantener el botón 4 s.
- **Huevo Comunitario:** la meta es **25 millones de Calor al mes**. Este número depende de cuánta gente juegue: con pocos servidores puede no llenarse nunca y con muchos se llenará el primer día. Ajústalo con datos reales.
  - Hacen falta 500 de Calor aportados para recibir la criatura conmemorativa, que es Épica.
- **Huevo Doble: no está hecho.** Necesita dos persecuciones a la vez, y `ChaseService`, el simulador y el HUD suponen un único portador. La propuesta: convertir el estado de la persecución en un objeto por huevo y llevarlo al simulador antes de activarlo. Es el siguiente bloque grande.

### 5. Bandada e intercambio
- **La Bandada no os hace aliados en la persecución** (para eso siguen los tratos). Lo decidí así para que cuatro amigos no sean imbatibles. El GDD no lo especifica.
- Al depositar, el 10 % de tu Afinidad se reparte entre el resto de la Bandada. El simulador lo modela: con 1000 partidas, la persecución no cambia.
- Con un amigo de Roblox en la Bandada se gana +10 % de polvo. Se aplica a todo el polvo de fin de ronda.
- **Intercambio:**
  - Solo criaturas (sin Monedas ni polvo), hasta 4 por lado, entre jugadores del mismo servidor.
  - Las Secretas también se pueden intercambiar.
  - No hay comisión ni nivel mínimo para intercambiar. Si te preocupan las cuentas secundarias, un mínimo de rondas jugadas sería fácil de añadir.

### 6. Ranking y salón de la fama
- El ranking cuenta solo los robos de la persecución, no los saqueos.
- Cada jugador puede dar 20 "me gusta" a la semana, uno por nido.
- El campeón de la semana pasada solo aparece en el cartel; todavía no recibe título ni premio.
- La semana empieza el lunes a las 00:00 UTC.

## Lo que el simulador no modela

- La Noche de Saqueo.
- El Huevo Comunitario.
- Los intercambios.
- Los "me gusta".

No cambian la persecución ni la producción del nido. El informe (`docs/simulacion.html`) está regenerado con todos los cambios: la criatura se escapa en un 1-2 % de las rondas y hay 9 robos por partida con 12 jugadores, como antes.
