<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class SuperappExportCommand extends Command
{
    protected $signature = 'superapp:export-all
                            {--tables=all : Comma separated table list or "all"}
                            {--format=json : json|csv}
                            {--chunk=2000 : Chunk size for streaming export}
                            {--path=exports/superapp : Relative output directory from project root}';

    protected $description = 'Export superapp master datasets (zones, modules, categories, brands, attributes and related tables) without changing database data.';

    private const DEFAULT_TABLES = [
        'modules',
        'module_zone',
        'zones',
        'categories',
        'attributes',
        'common_conditions',
        'brands',
        'parcel_categories',
        'addon_categories',
        'add_ons',
        'items',
        'stores',
        'units',
        'tags',
        'br_states',
        'br_cities',
        'br_neighborhoods',
        'postal_code_ranges',
        'zone_regions',
        'zone_region_polygons',
        'zone_region_neighborhoods',
        'zone_region_modules',
        'superapp_import_jobs',
        'superapp_import_errors',
        'superapp_data_quality_reports',
    ];

    public function handle(): int
    {
        $format = strtolower((string) $this->option('format'));
        if (!in_array($format, ['json', 'csv'], true)) {
            $this->error('Invalid --format value. Use json or csv.');
            return self::FAILURE;
        }

        $chunkSize = max(100, (int) $this->option('chunk'));
        $directory = trim((string) $this->option('path'), '/');
        $tables = $this->resolveTables((string) $this->option('tables'));

        if (empty($tables)) {
            $this->warn('No tables selected for export.');
            return self::SUCCESS;
        }

        $timestamp = now()->format('Ymd_His');
        $basePath = base_path("{$directory}/{$timestamp}");

        if (!is_dir($basePath) && !mkdir($basePath, 0755, true) && !is_dir($basePath)) {
            $this->error("Failed to create export directory: {$basePath}");
            return self::FAILURE;
        }

        $manifest = [
            'generated_at' => now()->toDateTimeString(),
            'format' => $format,
            'chunk_size' => $chunkSize,
            'base_path' => $basePath,
            'tables' => [],
        ];

        $this->info('Starting export...');

        foreach ($tables as $table) {
            if (!Schema::hasTable($table)) {
                $this->warn("Skipping {$table}: table not found.");
                $manifest['tables'][] = [
                    'table' => $table,
                    'status' => 'skipped_table_not_found',
                    'rows' => 0,
                    'file' => null,
                ];
                continue;
            }

            $filePath = "{$basePath}/{$table}.{$format}";
            $rows = $this->exportTable($table, $format, $filePath, $chunkSize);

            $manifest['tables'][] = [
                'table' => $table,
                'status' => 'exported',
                'rows' => $rows,
                'file' => $filePath,
            ];

            $this->line("- {$table}: {$rows} rows exported");
        }

        file_put_contents("{$basePath}/manifest.json", json_encode($manifest, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE));

        $this->info("Export completed. Files available at: {$basePath}");

        return self::SUCCESS;
    }

    /**
     * @return array<int, string>
     */
    private function resolveTables(string $tablesOption): array
    {
        $tablesOption = trim($tablesOption);
        if ($tablesOption === '' || strtolower($tablesOption) === 'all') {
            return self::DEFAULT_TABLES;
        }

        $tables = array_filter(array_map(static fn($table) => trim($table), explode(',', $tablesOption)));
        return array_values(array_unique($tables));
    }

    private function exportTable(string $table, string $format, string $filePath, int $chunkSize): int
    {
        return $format === 'csv'
            ? $this->exportTableToCsv($table, $filePath, $chunkSize)
            : $this->exportTableToJson($table, $filePath, $chunkSize);
    }

    private function exportTableToJson(string $table, string $filePath, int $chunkSize): int
    {
        $handle = fopen($filePath, 'wb');
        if (!$handle) {
            throw new \RuntimeException("Unable to open file for writing: {$filePath}");
        }

        fwrite($handle, "[");
        $first = true;
        $rowsCount = 0;

        DB::table($table)
            ->orderBy('id')
            ->chunk($chunkSize, function ($rows) use (&$first, &$rowsCount, $handle) {
                foreach ($rows as $row) {
                    if (!$first) {
                        fwrite($handle, ',');
                    }
                    fwrite($handle, json_encode((array) $row, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
                    $first = false;
                    $rowsCount++;
                }
            });

        fwrite($handle, "]");
        fclose($handle);

        return $rowsCount;
    }

    private function exportTableToCsv(string $table, string $filePath, int $chunkSize): int
    {
        $handle = fopen($filePath, 'wb');
        if (!$handle) {
            throw new \RuntimeException("Unable to open file for writing: {$filePath}");
        }

        $headerWritten = false;
        $rowsCount = 0;

        DB::table($table)
            ->orderBy('id')
            ->chunk($chunkSize, function ($rows) use (&$headerWritten, &$rowsCount, $handle) {
                foreach ($rows as $row) {
                    $data = (array) $row;
                    if (!$headerWritten) {
                        fputcsv($handle, array_keys($data));
                        $headerWritten = true;
                    }
                    fputcsv($handle, array_values($data));
                    $rowsCount++;
                }
            });

        fclose($handle);

        return $rowsCount;
    }
}
