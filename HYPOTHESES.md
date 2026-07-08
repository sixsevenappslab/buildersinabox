# BIAB — Hypothesis Log

> Registro vivo de hipótesis de negocio. Cada idea que surja (de Jesús, de un council, de
> research) entra aquí con el test más barato posible y sale como ✅ validada o ❌ refutada,
> con evidencia. Las ideas no se discuten dos veces: se consulta este log primero.
>
> Estados: 💡 propuesta · 🔬 validando · ✅ validada · ❌ refutada · 🧊 aparcada (post-gate)
>
> Export-ignored — no se publica. Los análisis largos viven en BIZ-PLAN-LIFESTYLE.md;
> el plan operativo en LAUNCH-PLAN.md. Aquí solo el estado de cada apuesta.

---

## H1 — "En 12 meses todo el mundo querrá esto; los Mac mini M1 usados subirán de 300€ a 500€"

- **Estado:** ❌ refutada (2026-07-07, strategy-council 5-0)
- **Evidencia en contra:** electrónica usada se deprecia (M1: −65% en 5 años); M4 mini nuevo
  16GB a ~600-700€ canibaliza cualquier M1 8GB usado a 500€; margen real por unidad ≈ 0€
  (horas config + envío + soporte + garantía legal de vendedor recurrente en España).
- **Lo que sobrevive de la idea:** la demanda de la *categoría* es real (ver H2); el error era
  el vehículo (especular con inventario). Derivada aceptada: **hardware bajo pedido, nunca stock**.

## H2 — "Existe demanda real de 'servidor personal de agentes' llave en mano"

- **Estado:** ✅ validada a nivel mercado (2026-07-08, market research) — pendiente a nivel BIAB
- **Evidencia a favor:** Mac minis M4 agotados en Asia (ene-feb 2026) como appliance no-oficial
  de agentes; PowerMining vende mini PC con agente preinstalado en Amazon; ACEMAGIC/Minisforum/
  GMKtec lanzando modelos; Hostinger vende "Claude Code VPS hosting" como categoría; el patrón
  Tailscale+tmux+Claude Code es ya "setup canónico" con guías dedicadas.
- **Matiz:** demanda de categoría ≠ demanda de BIAB. El test propio son las 6 semanas post-launch
  (gate en LAUNCH-PLAN §3).

## H3 — "El hueco diferencial de BIAB es 'seguro por defecto', no 'zero-touch'"

- **Estado:** 🔬 validando (se testea con el launch)
- **Evidencia a favor:** 42.665 instancias OpenClaw expuestas, 93,4% con auth bypass (feb 2026);
  todos los OEMs venden velocidad de setup, nadie vende hardening; BIAB ya es Tailscale-only.
- **Test:** el hook de seguridad en Show HN / r/selfhosted. Si el hilo tracciona por ese ángulo
  (comentarios, stars), la hipótesis gana; si el interés viene por otro lado, repivotar copy.

## H4 — "El modelo de monetización es el de Umbrel: OSS gratis → comunidad → caja bajo pedido"

- **Estado:** 🧊 aparcada hasta pasar el gate de 6 semanas
- **Evidencia a favor:** Umbrel 3,7M$ revenue 2024 con 5 empleados (OS gratis, caja 549$);
  Start9 caja 899$ con soporte lifetime. En contra: HA Yellow EOL (hardware sin comunidad previa
  muere). Precondición: tracción OSS primero (gate LAUNCH-PLAN §3).
- **Detalle:** BIZ-PLAN §5.4 (convenience pack, dropship, sin inventario).

## H5 — "Las pymes pagan implementación (~1 mes) + iguala mensual, con la caja como vehículo"

- **Estado:** 🔬 validando (sondeo, sin construir)
- **Origen:** Jesús, 2026-07-08. Análisis en BIZ-PLAN §5.5.
- **A favor:** la pyme compra resultado, no hierro → precios reales (1.500-3.000€ setup +
  150-400€/mes); encaja con hardware bajo pedido (H1-derivada).
- **En contra:** la iguala es obligación manual perpetua — solo compatible con el operating model
  si se diseña para ≤2h/mes/cliente; es un negocio distinto (agencia) que compite por las mismas
  horas que el launch.
- **Test (julio 2026):** Jesús sondea 2-3 pymes de su red con la pregunta "¿qué proceso te come
  más horas cada semana?". Pasa a 💡→✅ solo con una pyme con nombre, proceso concreto y
  disposición a pagar. Sin eso, se archiva en el checkpoint de septiembre.

## H6 — "Un extraño completa la instalación end-to-end sin ayuda"

- **Estado:** 🔬 validando (betas externas pre-flip, LAUNCH-PLAN §2)
- **Test:** 2-3 personas de la red instalan sin WhatsApp de rescate (una en VPS, una en mini PC,
  idealmente una con Gemini). 0/3 completan → no hay flip.

---

## Cómo añadir una hipótesis

Una entrada nueva = 4 líneas: enunciado falsable, estado, evidencia conocida, y el test más
barato que la mataría. Si no tiene test barato, no es hipótesis: es opinión — va al BIZ-PLAN.
