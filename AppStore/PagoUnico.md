# Tracey — Venta con pago único

Tracey se vende como **app de pago**: el cliente paga una vez en la App Store y tiene todo. No hay suscripción, ni compras dentro de la app, ni versión gratuita.

El **Acuerdo de Apps de Pago** (Paid Apps Agreement) no se redacta: es un contrato estándar de Apple que aceptas en App Store Connect. Mientras no esté activo, solo puedes publicar apps gratis. Aquí están los pasos para activarlo y poner el precio.

---

## 1. Activar el Acuerdo de Apps de Pago

App Store Connect → **Negocios** (Business):

1. **Acepta el Paid Apps Agreement.** Tiene que hacerlo el titular de la cuenta (Account Holder).
2. **Cuenta bancaria:** agrega una cuenta a tu nombre (o al de tu empresa) en pesos mexicanos. Apple te paga ahí.
3. **Información fiscal:**
   - **Formulario de EE. UU.:** como persona física en México llenas el **W-8BEN**. Sirve para que Apple no te retenga impuestos de EE. UU. por ventas allá.
   - **México:** Apple te pide tus datos fiscales (RFC). Por la ley de plataformas digitales, Apple retiene ISR e IVA de tus ventas en México y la retención es mayor si no das tu RFC. **Revísalo con tu contador** antes de las primeras ventas.
4. **Contactos:** llena los contactos financiero, legal y técnico. Pueden ser todos tú.

El estado tiene que quedar como **Activo**. Apple puede tardar desde unas horas hasta un par de días en validarlo.

## 2. Únete al Small Business Program (importante)

Por defecto Apple se queda con el **30 %**. Con el App Store Small Business Program (ingresos menores a 1 millón de dólares al año) la comisión baja al **15 %**. No es automático: hay que solicitarlo en developer.apple.com → App Store Small Business Program, después de activar el Acuerdo de Apps de Pago.

## 3. Poner el precio

App Store Connect → Tracey → **Precios y disponibilidad**:

1. **País base: México.** Así eliges el precio en pesos y Apple calcula el equivalente en los demás países.
2. **Precio:** elige el punto de precio en MXN que prefieras. Apple solo ofrece montos fijos; busca **MX$49** o **MX$99**, o el más cercano.
3. **Disponibilidad:** todos los países, o solo México y Latinoamérica si quieres empezar en chico.
4. **No crees compras dentro de la app.** Con eso la app queda como pago único.

### Cuánto te queda por venta (estimado)

Los precios de la App Store en México ya incluyen IVA (16 %), y la comisión de Apple se calcula sin el IVA:

| Precio | Sin IVA | Te queda con 15 % de comisión | Te queda con 30 % |
|---|---|---|---|
| MX$49 | ≈ $42.24 | **≈ $35.90** | ≈ $29.57 |
| MX$99 | ≈ $85.34 | **≈ $72.54** | ≈ $59.74 |

A eso se le resta la retención de ISR que aplica Apple en México. Confirma el porcentaje con tu contador.

**Sugerencia:** lanza a **MX$49**. Es una compra por impulso y compite contra apps "gratis" que luego cobran una suscripción. Si las reseñas salen buenas, súbelo a MX$99 después. Los que ya compraron no pagan otra vez.

## 4. Lo que Apple ya resuelve por ti

- **Cobro y facturación al cliente:** Apple es el vendedor ante el comprador.
- **Reembolsos:** el cliente los pide en reportaproblem.apple.com; no tienes que gestionarlos.
- **Licencia de uso:** aplica el EULA estándar de Apple, así que no necesitas términos propios.
- **Otros dispositivos y familia:** quien compra puede instalar la app en todos sus dispositivos con el mismo Apple ID, y compartirla con Compartir en familia.
- **Actualizaciones:** son gratis para quien ya compró. El pago único cubre las versiones futuras.

## 5. Publicar la política de privacidad y el soporte

App Store Connect te pide dos URL públicas. Las páginas ya están en el repo: [`docs/privacidad.html`](../docs/privacidad.html) y [`docs/soporte.html`](../docs/soporte.html).

1. El correo de soporte ya está puesto: sergionvtedev@icloud.com.
2. En GitHub: repo **Tracey** → Settings → **Pages** → Source: *Deploy from a branch* → Branch: `main`, carpeta `/docs` → Save.
3. En un par de minutos quedan en:
   - Privacidad: `https://sergionvte.github.io/Tracey/privacidad.html`
   - Soporte: `https://sergionvte.github.io/Tracey/soporte.html`

## Checklist antes de mandar a revisión

- [ ] Acuerdo de Apps de Pago **Activo** (banco, impuestos, contactos)
- [ ] Solicitud al Small Business Program
- [ ] Precio en MXN con México como país base
- [ ] Ficha en español e inglés ([Ficha.md](Ficha.md))
- [ ] Capturas de iPhone 6.9" y iPad 13"
- [ ] Páginas de privacidad y soporte publicadas
- [ ] Privacidad de la app: "Datos no recopilados"
- [ ] Clasificación por edad: 4+
- [ ] Build subido con Xcode (Apple ID agregado en Xcode → Settings → Accounts)

## Versionado

- **Versión** (la que ve la gente): **1.0**. Solo cambia a mano cuando sale una versión nueva a la App Store (1.1, 1.2…).
- **Build**: el número de commits (`git rev-list --count HEAD`), así siempre sube y App Store Connect no rechaza un build repetido.
- **.ipa de prueba** (sin firmar, para LiveContainer): `Tools/make-ipa.sh` → `build/Tracey-1.0-unsigned.ipa`, con el build ya puesto.
- **Subir desde Xcode**: antes de *Product → Archive*, poner ese número en Tracey → General → Build.
