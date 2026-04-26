<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        if (!Schema::hasTable('superapp_import_jobs')) {
            Schema::create('superapp_import_jobs', function (Blueprint $table) {
                $table->id();
                $table->string('command_name', 120)->index();
                $table->string('source', 80)->nullable()->index();
                $table->json('options')->nullable();
                $table->enum('status', ['running', 'completed', 'failed', 'completed_with_errors'])->default('running')->index();
                $table->boolean('dry_run')->default(true)->index();
                $table->unsignedBigInteger('processed_rows')->default(0);
                $table->unsignedBigInteger('inserted_rows')->default(0);
                $table->unsignedBigInteger('updated_rows')->default(0);
                $table->unsignedBigInteger('skipped_rows')->default(0);
                $table->unsignedBigInteger('error_rows')->default(0);
                $table->string('manifest_path', 255)->nullable();
                $table->text('summary')->nullable();
                $table->dateTime('started_at')->nullable()->index();
                $table->dateTime('finished_at')->nullable()->index();
                $table->timestamps();
            });
        }

        if (!Schema::hasTable('superapp_import_errors')) {
            Schema::create('superapp_import_errors', function (Blueprint $table) {
                $table->id();
                $table->foreignId('job_id')->nullable()->index();
                $table->unsignedBigInteger('row_number')->nullable()->index();
                $table->string('external_key', 191)->nullable()->index();
                $table->text('error_message');
                $table->json('payload')->nullable();
                $table->timestamps();
            });
        }

        if (!Schema::hasTable('superapp_data_quality_reports')) {
            Schema::create('superapp_data_quality_reports', function (Blueprint $table) {
                $table->id();
                $table->string('report_name', 120)->index();
                $table->json('metrics');
                $table->json('notes')->nullable();
                $table->enum('status', ['ok', 'warning', 'critical'])->default('ok')->index();
                $table->timestamps();
            });
        }

        if (Schema::hasTable('superapp_import_jobs') && Schema::hasTable('superapp_import_errors')) {
            Schema::table('superapp_import_errors', function (Blueprint $table) {
                $table->foreign('job_id')->references('id')->on('superapp_import_jobs')->nullOnDelete();
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('superapp_data_quality_reports');
        Schema::dropIfExists('superapp_import_errors');
        Schema::dropIfExists('superapp_import_jobs');
    }
};
