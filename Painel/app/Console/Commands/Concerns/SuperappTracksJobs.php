<?php

namespace App\Console\Commands\Concerns;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

trait SuperappTracksJobs
{
    protected ?int $jobId = null;
    protected array $jobStats = [
        'processed_rows' => 0,
        'inserted_rows' => 0,
        'updated_rows' => 0,
        'skipped_rows' => 0,
        'error_rows' => 0,
    ];

    protected function startSuperappJob(string $commandName, string $source, array $options, bool $dryRun): void
    {
        if (!Schema::hasTable('superapp_import_jobs')) {
            return;
        }

        $this->jobId = DB::table('superapp_import_jobs')->insertGetId([
            'command_name' => $commandName,
            'source' => $source,
            'options' => json_encode($options, JSON_UNESCAPED_UNICODE),
            'status' => 'running',
            'dry_run' => $dryRun ? 1 : 0,
            'started_at' => now(),
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }

    protected function finishSuperappJob(string $status, ?string $manifestPath = null, ?string $summary = null): void
    {
        if (!$this->jobId || !Schema::hasTable('superapp_import_jobs')) {
            return;
        }

        DB::table('superapp_import_jobs')->where('id', $this->jobId)->update([
            'status' => $status,
            'manifest_path' => $manifestPath,
            'summary' => $summary,
            'processed_rows' => $this->jobStats['processed_rows'],
            'inserted_rows' => $this->jobStats['inserted_rows'],
            'updated_rows' => $this->jobStats['updated_rows'],
            'skipped_rows' => $this->jobStats['skipped_rows'],
            'error_rows' => $this->jobStats['error_rows'],
            'finished_at' => now(),
            'updated_at' => now(),
        ]);
    }

    protected function logImportError(int $rowNumber, ?string $externalKey, string $errorMessage, ?array $payload = null): void
    {
        $this->jobStats['error_rows']++;

        if (!$this->jobId || !Schema::hasTable('superapp_import_errors')) {
            return;
        }

        DB::table('superapp_import_errors')->insert([
            'job_id' => $this->jobId,
            'row_number' => $rowNumber,
            'external_key' => $externalKey,
            'error_message' => $errorMessage,
            'payload' => $payload ? json_encode($payload, JSON_UNESCAPED_UNICODE) : null,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }

    protected function createManifest(string $commandName, array $payload): string
    {
        $directory = storage_path('app/superapp/manifests');
        if (!is_dir($directory)) {
            mkdir($directory, 0755, true);
        }

        $fileName = sprintf('%s_%s.json', str_replace(':', '_', $commandName), now()->format('Ymd_His_u'));
        $filePath = $directory . '/' . $fileName;
        file_put_contents($filePath, json_encode($payload, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE));

        return str_replace(base_path() . '/', '', $filePath);
    }
}
