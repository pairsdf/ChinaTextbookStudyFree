import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

/** @type {import('next').NextConfig} */
const nextConfig = {
  output: "export",
  images: { unoptimized: true },
  trailingSlash: true,
  transpilePackages: ["@cstf/core"],
  // monorepo：固定 tracing 根目录，避免多 lockfile 误判
  outputFileTracingRoot: path.join(__dirname, "../.."),
  experimental: {
    // 约 3900 静态页：降低并发，避免 Windows / 高版本 Node 下 worker OOM
    staticGenerationMaxConcurrency: 2,
    staticGenerationMinPagesPerWorker: 50,
  },
};

export default nextConfig;
