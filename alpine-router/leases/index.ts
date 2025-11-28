const LEASES_FILE = "./data/dnsmasq.leases";

interface Lease {
  expiry: string;
  mac: string;
  ip: string;
  hostname: string;
  clientId: string;
  expiryTimestamp?: number;
  isStatic: boolean;
  hoursRemaining?: number;
}

async function parseLeases(): Promise<Lease[]> {
  const leases: Lease[] = [];

  try {
    const content = await Bun.file(LEASES_FILE).text();
    const lines = content.trim().split("\n");

    for (const line of lines) {
      const parts = line.split(/\s+/);
      if (parts.length >= 5) {
        const [expiry, mac, ip, hostname, clientId] = parts as [
          string,
          string,
          string,
          string,
          string,
        ];

        const lease: Lease = {
          expiry,
          mac,
          ip,
          hostname,
          clientId,
          isStatic: expiry === "0",
        };

        if (!lease.isStatic) {
          lease.expiryTimestamp = parseInt(expiry);
          const now = Math.floor(Date.now() / 1000);
          const remaining = lease.expiryTimestamp - now;
          lease.hoursRemaining = Math.floor(remaining / 3600);
        }

        leases.push(lease);
      }
    }
  } catch (err) {
    console.error("Error reading leases:", err);
  }

  return leases;
}

function formatLeasesText(leases: Lease[]): string {
  let output = "Cekahanafi Infrastructure Servers\n";
  output += "==================================\n\n";

  const header = `${"Hostname".padEnd(20)} ${"IP".padEnd(15)} ${"MAC".padEnd(17)} ${"Type".padEnd(10)}`;
  output += header + "\n";
  output += `${"--------".padEnd(20)} ${"--".padEnd(15)} ${"---".padEnd(17)} ${"----".padEnd(10)}\n`;

  for (const lease of leases) {
    const type = lease.isStatic
      ? "Static"
      : `Dynamic (${lease.hoursRemaining}h)`;
    output += `${lease.hostname.padEnd(20)} ${lease.ip.padEnd(15)} ${lease.mac.padEnd(17)} ${type.padEnd(10)}\n`;
  }

  output += "\n";
  output += "Quick Access:\n";
  output += "  ssh root@<hostname>\n\n";
  output += "Examples:\n";
  for (const lease of leases.slice(0, 3)) {
    output += `  ssh root@${lease.hostname}\n`;
  }

  return output;
}

const server = Bun.serve({
  port: 3000,
  //   hostname: "192.168.200.1",
  routes: {
    "/api/leases": async () => {
      const leases = await parseLeases();
      return new Response(JSON.stringify(leases, null, 2), {
        headers: { "Content-Type": "application/json" },
      });
    },
    "/leases.txt": () => {
      const file = Bun.file(LEASES_FILE);
      return new Response(file);
    },
    "/": async () => {
      const leases = await parseLeases();
      const text = formatLeasesText(leases);
      return new Response(text, {
        headers: { "Content-Type": "text/plain; charset=utf-8" },
      });
    },
  },
});

console.log(`🚀 Leases server running on http://192.168.200.1:${server.port}`);
