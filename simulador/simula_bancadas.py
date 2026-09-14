"""
Simulador de bancadas do SAAP.

Publica mensagens MQTT como se fossem nós de bancada reais, para testar
Node-RED + PostgreSQL + Grafana sem precisar do hardware.

Uso:
    pip install paho-mqtt
    python simula_bancadas.py                 # 3 bancadas, ritmo acelerado
    python simula_bancadas.py --broker localhost --bancadas B01 B02 B03 B04
    python simula_bancadas.py --micro-parada B02   # B02 para de produzir após 60 s
"""
import argparse
import datetime
import json
import random
import time

import paho.mqtt.client as mqtt


def agora_iso():
    # microssegundos: cada evento tem um timestamp único.
    # Este simulador já envia evt_id, então a deduplicação forte por
    # (bancada, evt_id) é quem manda (ver postgres/init/001_schema.sql).
    # Mas o firmware real ainda não envia evt_id, caindo no índice por
    # (bancada, ts) — aí sim, dois eventos com o mesmo segundo colidiriam
    # e um seria descartado pelo ON CONFLICT DO NOTHING.
    return datetime.datetime.now(datetime.timezone.utc).astimezone().isoformat(timespec="microseconds")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--broker", default="localhost")
    ap.add_argument("--port", type=int, default=1883)
    ap.add_argument("--setor", default="setorA")
    ap.add_argument("--bancadas", nargs="+", default=["B01", "B02", "B03"])
    ap.add_argument("--intervalo", type=float, default=2.0,
                    help="segundos médios entre peças (todas as bancadas juntas)")
    ap.add_argument("--micro-parada", default=None,
                    help="id de bancada que deixa de produzir após 60 s")
    args = ap.parse_args()

    cli = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="simulador-saap")
    cli.connect(args.broker, args.port, 60)
    cli.loop_start()

    total = {b: 0 for b in args.bancadas}
    total_hora = {b: 0 for b in args.bancadas}
    seq = {b: 0 for b in args.bancadas}
    hora_atual = datetime.datetime.now().hour
    t0 = time.time()

    print(f"Publicando em fabrica/{args.setor}/bancada/<id>/evento  (Ctrl+C para parar)")
    try:
        while True:
            b = random.choice(args.bancadas)

            if args.micro_parada and b == args.micro_parada and (time.time() - t0) > 60:
                time.sleep(random.uniform(0.5, 1.5))
                continue

            h = datetime.datetime.now().hour
            if h != hora_atual:
                hora_atual = h
                for k in total_hora:
                    total_hora[k] = 0

            total[b] += 1
            total_hora[b] += 1
            seq[b] += 1

            msg = {
                "bancada": b,
                "evt_id": f"{b}-{seq[b]:06d}",
                "ts": agora_iso(),
                "delta": 1,
                "total_turno": total[b],
                "total_hora": total_hora[b],
                "origem": "sensor",
            }
            topico = f"fabrica/{args.setor}/bancada/{b}/evento"
            cli.publish(topico, json.dumps(msg), qos=1)
            print("->", topico, msg)
            time.sleep(random.expovariate(1.0 / args.intervalo))
    except KeyboardInterrupt:
        print("\nencerrando")
    finally:
        cli.loop_stop()
        cli.disconnect()


if __name__ == "__main__":
    main()
