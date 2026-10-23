# GDD v2: qué se ha cambiado, qué revisar y qué más mejoraría

Este documento resume la **versión 2** de las mecánicas y termina con un **nuevo repaso** de lo que todavía podría mejorarse. El GDD actualizado está en [`GDD.md`](GDD.md). Su sección 12 explica cada cambio y la sección **(v2)** de cada mecánica cuenta el porqué.

## Resultado, medido con el simulador

30 días con 72 bots de 6 tipos y **las mismas horas de juego** en las dos versiones (las sesiones se miden en minutos). Las gráficas están en [`simulacion.html`](simulacion.html).

| | v1 | v2 |
|---|---|---|
| Duración de la ronda | 11,5 min | 6,0 min |
| Victorias por hora de juego | 0,53 | 2,29 |
| Sesiones con alguna victoria | 24 % | 71 % |
| Novato: victorias por hora | 0 | 0,34 |
| Casual: victorias por hora | 0,02 | 0,9 |
| El elegido conserva su criatura (12 jugadores) | 9 % | 36 % |
| Robos por criatura (12 jugadores) | 8,5 | 3,5 |
| La criatura escapa | ~0 % | ~0 % |
| Nuevas generaciones al mes (media) | 0,62 | 0,72 |

**Nada de esto se ha probado aún dentro de Roblox Studio.** Todo pasa los 44 tests, el análisis de tipos y la compilación, y el simulador juega con las mismas reglas que el servidor. Pero la eclosión nueva, el tira y afloja, los zorros y el compañero hay que verlos en Studio con [`PRUEBAS.md`](PRUEBAS.md).

## Decisiones que debes revisar

Todas están en `src/shared/Config.luau` salvo la Secreta (en `Rarity.luau`).

1. **Rondas de ~6 min** (`Config.Round`): incubación 210 s, eclosión 10 s, persecución 120 s, prórroga 30 s, resultados 8 s y preparados 6 s. Son mi propuesta; el simulador dice que funcionan, pero el "ritmo" se juzga jugando.
2. **Varias criaturas por ronda** (`PlayersPerCreature = 5`, `MaxCreatures = 3`). Con 2-6 jugadores sale 1; con 7-11, 2; con 12 o más, 3. Con una sola criatura para 8 jugadores el elegido solo la conservaba el 13 % de las veces. Si quieres que una criatura sea más especial, sube `PlayersPerCreature` (con 6: 1 hasta 7 jugadores, 2 hasta 13, luego 3).
3. **Escudos de Afinidad**: 1 por cada 800 de Calor, máximo 1 (`Config.Shields`). Con 2 escudos o más baratos, el portador casi siempre ganaba (82 % aseguradas).
4. **Robo por toque** (`Chase.TapSteal = true`) y **asegurar en 30 s** (`Chase.SecureSeconds`). Con `false` vuelve el "mantener el botón".
5. **Precios ×2,5** (`PriceScale = 2.5`). Con 4,6 veces más victorias por hora, sin esto las Monedas se multiplicaban casi por 3 y las Nuevas generaciones llegaban el doble de rápido. Afecta a mejoras, cría, Nueva generación y decoración de Monedas.
6. **Inactivos fuera de la Elección y sin consuelo** (`Election.RequireActivity`). Ojo al probar en Studio: si dejas a Player1 quieto, no saldrá elegido.
7. **Zorros del bosque** con menos de 6 jugadores (`Config.ForestThieves`). En una prueba con 4 jugadores salen 2 zorros. Nunca se quedan la criatura: la tiran al suelo.
8. **Pago por ganar retirado**: se quitan el Escudo de Cáscara de pago y la Bolsa Grande (+50 % de Calor), que pasa a ser la **Estela de Brasas** (estética). Si querías esos ingresos, ver el punto 10 del repaso.
9. **Secreta 1 entre 50.000** (`Rarity.luau`, peso 20 sobre 1.000.000). Es una estimación: habría que ajustarla al volumen real de eclosiones.
10. **Favoritas**: 3, sobreviven a la Nueva generación. El compañero es solo estético.
11. **Noche de Saqueo como fase propia** de 60 s tras los resultados (`Events.LootNight.PhaseSeconds`). Sigue en versión prudente (`OwnerLoses = false`).
12. **Luna de Sangre en 3 franjas** los sábados (02:00, 12:00 y 20:00 UTC).
13. **"Liberar guardadas" también libera Raras** (`Release.BulkMaxRarity`): en la v2 casi no salen Comunes.

Decisiones anteriores que siguen abiertas: la meta del Huevo Comunitario (25 millones al mes, depende de cuánta gente juegue), que la Bandada no dé alianza automática y que se puedan intercambiar Secretas.

La versión de Claude Docs del GDD (el documento original) **no se ha tocado**. Se ha actualizado `docs/GDD.md` del repositorio.

---

## Nuevo repaso: qué más se podría mejorar

Con la v2 en el simulador han salido problemas nuevos, y quedan pendientes algunos de antes. Ordenados por importancia.

### Problemas de fondo

**1. Los huevos personales eclipsan a la persecución.** En un mes, un jugador muy activo abre **866 huevos personales** y gana unas 250 criaturas persiguiendo. El polvo sobra (unas 100.000 al mes para un jugador muy activo), así que la incubadora siempre está llena de huevos de 100 de polvo. El premio de la ronda pierde valor, porque las criaturas te llegan solas.
- Además, **la cría casi no se usa**: los jugadores activos crían 0-0,3 veces al mes, porque la única ranura de la incubadora siempre está ocupada. Es un sistema entero que no aporta.
- *Propuesta:*
  - limitar los huevos personales (por ejemplo, 3 al día) y que cuesten más;
  - dar a la cría una ranura propia;
  - llevar el polvo sobrante a cosas sin efecto en la ronda: decoración, accesorios del compañero o re-tirar un gen.

**2. Inflación de rarezas.** En la v2, el **58 %** de las criaturas de los nidos son Épicas (en la v1, lo más común era la Rara, con un 51 %). Ocurre porque la barra garantiza Rara desde el 25 % y Épica desde el 75 %, y ahora salen 4,6 veces más criaturas. Si todo es Épico, nada es emocionante.
- *Propuesta:* que la garantía de la barra se aplique solo a la **primera** criatura de la ronda (las demás, con la tirada normal), y subir el umbral de la Rara al 50 %.

**3. La brecha de habilidad sigue siendo enorme.** Los novatos ya ganan (0,34 por hora), pero los jugadores hábiles ganan unas **10 veces más** (3,3 por hora).
- *Propuesta:*
  - **emparejamiento por nivel**: las primeras horas de un jugador, en servidores de novatos;
  - o un hándicap suave: quien ha ganado mucho recientemente necesita más Calor por escudo.

**4. La Afinidad da doble ventaja a los veteranos.** La bolsa mejorada lleva hasta 10 veces más Calor (de 100 a 1.000). Más Calor da más probabilidad de ser elegido **y**, desde la v2, más escudos.
- *Propuesta:*
  - rendimientos decrecientes en la Elección (que cuente la raíz cuadrada de la Afinidad);
  - o que las mejoras de bolsa a partir de cierto nivel den velocidad de recogida en vez de capacidad.

**5. Demasiados sistemas para el público objetivo (9-13 años).** Hay Calor, Afinidad, escudos, Monedas, polvo, mejoras, cría, incubadora, Nueva generación, favoritas, decoración, misiones, racha, Bandada, tratos, intercambio, ranking, me gusta, Huevo Comunitario y Noche de Saqueo. Es mucho para la primera hora.
- *Propuesta:* **desbloqueo progresivo**. Por ejemplo:
  - la tienda y las mejoras, desde el principio;
  - la cría, con 3 criaturas;
  - los tratos, desde la ronda 5;
  - el intercambio, tras 2 horas de juego;
  - la Nueva generación, cuando te acercas.

  Cada sistema nuevo llega con su aviso.

### Lo que más ayudaría a la retención

**6. Tutorial guiado y sonido.** Siguen pendientes desde la v1 y son lo que más pesa en la retención del primer día. El GDD llama al latido del huevo "la firma sonora del juego", y el juego todavía no tiene sonido.

**7. Botón de acción contextual en móvil.** Hay muchas teclas: E, F, Q, R, T, G y Shift. Tocar un prompt pequeño sobre alguien que corre es difícil en móvil. El GDD ya pedía "un botón de acción contextual (recoger / depositar / robar / pasar)".
- *Propuesta:* un botón grande que cambie según el contexto.

**8. Que los robos también tengan su ranking de defensa.** El ranking semanal solo premia robar. Un "ranking de criaturas aseguradas" y títulos semanales (por ejemplo, "Guardián del Nido") premiarían también defender.

### Antes de publicar

**9. Seguridad de movimiento.** El servidor fija la velocidad y valida distancias en cada robo y depósito, pero no detecta un **teletransporte** (un cliente modificado puede mover su personaje).
- *Propuesta:* comprobar la velocidad real entre muestras (posición cada 0,5 s) y registrar anomalías, antes de abrir el juego.

**10. Intercambio y dinero real.** Con Secretas intercambiables, aparecerán cuentas secundarias y ventas por dinero real fuera de Roblox.
- *Propuesta:*
  - intercambio desbloqueado tras X horas de juego;
  - límite diario;
  - Secretas y Míticas intransferibles los primeros 7 días;
  - aviso si los valores de las dos ofertas son muy distintos.

**11. Ingresos sin pago por ganar.** Al quitar el Escudo de pago y la Bolsa Grande, los ingresos dependen de la Suerte del Servidor, los pases de comodidad y la suscripción.
- *Propuesta:*
  - el compañero abre un catálogo natural de **cosméticos**: sombreros, estelas y accesorios para tu criatura favorita;
  - temas de nido;
  - **poner nombre** a tus criaturas, filtrado con `TextService` (refuerza el apego).

**12. Accesibilidad.** La rareza se distingue sobre todo por el color.
- *Propuesta:* añadir icono o texto en el mundo (no solo en el panel) para jugadores daltónicos, y un ajuste de tamaño de interfaz.

**13. Medir en la beta lo que predice el simulador.** Los bots persiguen en línea recta, sin árboles ni física.
- *Propuesta:* añadir a la analítica las métricas de la tabla de arriba (victorias por sesión, robos por criatura, el elegido conserva, rondas por sesión) para comprobar en la beta cerrada si los números se parecen.

### Lo primero, siempre

**14. Probar en Studio.** Sigue siendo el paso más importante: [`PRUEBAS.md`](PRUEBAS.md) tiene la lista con lo nuevo de la v2. Con 4 jugadores verás también los zorros.
