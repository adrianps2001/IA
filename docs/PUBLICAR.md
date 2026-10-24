# Cómo poner a la venta las cosas del juego (Robux)

Guía paso a paso para crear en Roblox lo que se vende en The Egg Chooses y conectarlo con el juego. Todo se hace en el **Creator Hub** (https://create.roblox.com) con tu cuenta. El código ya está listo: solo hay que crear los productos y copiar sus números a `src/shared/Config.luau`.

Para publicar el lobby y las partidas en dos lugares, mira el final de `docs/PRUEBAS.md`.

---

## 1. Las tres formas de cobrar en Roblox

| Tipo | Cuándo se usa | En el juego |
|---|---|---|
| **Game pass** | Pago **una sola vez** y es tuyo para siempre | Nido VIP, x2 Monedas, Incubadora Rápida, Ranura de cría, Estela de Brasas (`Config.GamePasses`) |
| **Developer product** | Se puede comprar **muchas veces** (o una cosa concreta de una lista) | Suerte del Lobby, Huevo de Temporada, packs de Monedas (`Config.DevProducts`) y **cada artículo de la Tienda de la Plaza** (`Config.CosmeticProducts`) |
| **Suscripción** | Pago **cada mes** | Club del Nido (`Config.ClubSubscriptionId`) |

De lo que pague el jugador, a ti te llega aproximadamente el 70 % en Robux.

---

## 2. Tienda de la Plaza con Robux

### Qué es

La pestaña **Plaza** del panel del nido vende **sombreros** para la criatura al hombro y **temas** para el nido (invierno, playa, caramelo, volcán y espacio). Cada día salen 6 artículos distintos (los mismos para todo el mundo). Siempre se pueden comprar con **polvo de cáscara**. Si además creas un producto de Robux para un artículo, al lado del precio en polvo sale un botón verde **R$ (precio)**.

Es solo estética: no da ninguna ventaja en la partida.

### Paso a paso (una vez por artículo)

1. Entra en el Creator Hub → **Creaciones** → tu experiencia → menú de la izquierda **Monetización** → **Productos para desarrolladores** (Developer Products).
2. Pulsa **Crear un producto para desarrolladores**.
3. Rellena:
   - **Nombre:** el del artículo, por ejemplo `Chistera`. Es lo que verá el jugador en la ventana de compra.
   - **Descripción:** por ejemplo `Sombrero para tu criatura al hombro`.
   - **Imagen:** un icono cuadrado de 512×512 (opcional, pero queda mucho mejor).
   - **Precio en Robux:** lo eliges tú. Recomendado: sombreros entre 25 y 75 Robux; temas de nido entre 99 y 199 Robux.
4. Guarda. Copia el **ID del producto** (un número largo, por ejemplo `1234567890`). Aparece en la lista de productos y en la URL.
5. Abre `src/shared/Config.luau`, busca `Config.CosmeticProducts` y pon el número en el artículo:
   ```lua
   Config.CosmeticProducts = {
       hat_top = 1234567890, -- Chistera
       ...
   }
   ```
   Los que dejes a `0` solo se venden con polvo. Si no sabes cuál es cuál, el nombre del artículo está en `src/shared/Cosmetics.luau` (`hat_top` = Chistera, `theme_space` = Nido espacial…).
6. Vuelve a generar el archivo del juego (o pídemelo) y publícalo en los dos lugares.

Los 13 identificadores son: `hat_party` (Gorro de fiesta), `hat_beanie` (Gorro de lana), `hat_bow` (Lazo), `hat_flowers` (Corona de flores), `hat_glasses` (Gafas de sol), `hat_top` (Chistera), `hat_pirate` (Sombrero pirata), `hat_crown` (Coronita), `theme_snow` (Nido de invierno), `theme_beach` (Nido de playa), `theme_candy` (Nido de caramelo), `theme_volcano` (Nido volcánico) y `theme_space` (Nido espacial).

### Cómo funciona por dentro

1. **El botón.** El cliente (`NestController`) ve que el artículo tiene un número en `Config.CosmeticProducts` y enseña el botón **R$**. El precio no está en el código: se lo pregunta a Roblox (`GetProductInfoAsync`), así que si lo cambias en el Creator Hub, el juego enseña el nuevo sin tocar nada.
2. **La compra.** Al pulsarlo, el cliente llama a `PromptProductPurchase` y Roblox enseña **su propia ventana** de compra. El juego nunca ve ni toca el dinero.
3. **El recibo.** Si el jugador paga, Roblox avisa al **servidor** llamando a `ProcessReceipt` (en `MonetizationService`). Ese recibo dice quién compró y qué producto.
4. **La entrega.** `ShopService` registró al arrancar qué hacer con cada producto: dárselo al jugador (pasa a "Lo tuyo") y ponérselo. Si ya lo tenía (por ejemplo, pulsó dos veces), se le devuelve el valor en polvo para que no pierda nada.
5. **Guardar antes de confirmar.** `MonetizationService` guarda el perfil y apunta el número del recibo **antes** de decirle a Roblox "entregado". Si el servidor se cae a mitad, Roblox vuelve a mandar el recibo más tarde; como el número ya está apuntado, no se entrega dos veces. Y si no se pudo guardar, se responde "aún no", y Roblox lo reintenta.

### Cómo probarlo

- **En Studio** las compras son de mentira (no cobran) y Roblox enseña la ventana igual: sirve para comprobar que el artículo se entrega y se pone.
- **En el juego publicado**, prueba primero con un precio bajo (por ejemplo, 1 Robux) y luego pon el precio real.
- Comprueba: sale el botón R$ con el precio, al pagar el artículo aparece en "Lo tuyo" y se lo pone la criatura (o se pinta el nido), y al salir y volver a entrar sigue siendo tuyo.

---

## 3. Los demás productos y pases

Mismo proceso (Creator Hub → Monetización), copiando cada número a su sitio en `src/shared/Config.luau`:

| Qué | Dónde se crea | Dónde va el número |
|---|---|---|
| Nido VIP, x2 Monedas, Incubadora Rápida, Ranura de cría extra, Estela de Brasas | **Pases** | `Config.GamePasses` |
| Suerte del Lobby, Huevo de Temporada, Repetir cría, packs de Monedas | **Productos para desarrolladores** | `Config.DevProducts` |
| Club del Nido | **Suscripciones** (empieza por `EXP-`) | `Config.ClubSubscriptionId` |

Los precios recomendados están en el GDD (sección 9).
