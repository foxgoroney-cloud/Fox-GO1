<?php

namespace App\Console\Commands;

use App\Console\Commands\Concerns\SuperappTracksJobs;
use Illuminate\Console\Command;

class SuperappSkuImportCommand extends Command
{
    use SuperappTracksJobs;

    protected $signature = 'superapp:sku-import {--source=csv} {--file=storage/imports/skus.csv} {--chunk=5000} {--dry-run}';
    protected $description = 'Importador massivo de SKUs em chunks (modo infra)';

    public function handle(): int
    {
        $dryRun = (bool)$this->option('dry-run');
        $file = base_path((string)$this->option('file'));
        $chunk = max(500, (int)$this->option('chunk'));
        $this->startSuperappJob($this->getName(), 'csv', $this->options(), $dryRun);

        if (!is_file($file)) {
            $this->error("CSV not found: {$file}");
            return self::FAILURE;
        }

        $seen = [];
        $csv = new \SplFileObject($file);
        $csv->setFlags(\SplFileObject::READ_CSV | \SplFileObject::SKIP_EMPTY);
        $headers = null;

        foreach ($csv as $index => $line) {
            if ($index === 0) {
                $headers = array_map('trim', (array)$line);
                continue;
            }

            if (!$headers || $line === [null]) {
                continue;
            }

            $row = array_combine($headers, array_pad((array)$line, count($headers), null));
            $this->jobStats['processed_rows']++;
            $sku = trim((string)($row['sku'] ?? ''));

            if ($sku === '') {
                $this->logImportError($index + 1, null, 'SKU vazio', $row);
                continue;
            }

            if (isset($seen[$sku])) {
                $this->jobStats['skipped_rows']++;
                $this->logImportError($index + 1, $sku, 'SKU duplicado no arquivo', $row);
                continue;
            }

            $seen[$sku] = true;
            $this->jobStats['inserted_rows']++;

            if (($this->jobStats['processed_rows'] % $chunk) === 0) {
                $this->line("Processed {$this->jobStats['processed_rows']} rows...");
            }
        }

        $manifest = $this->createManifest($this->getName(), ['stats' => $this->jobStats, 'dry_run' => $dryRun, 'mode' => 'infra-only']);
        $this->finishSuperappJob($this->jobStats['error_rows'] ? 'completed_with_errors' : 'completed', $manifest, 'SKU import infra validation done');

        return self::SUCCESS;
    }
}
