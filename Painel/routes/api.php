<?php

use Illuminate\Support\Facades\Route;

Route::prefix('v1')->namespace('App\Http\Controllers')->group(base_path('routes/api/v1/api.php'));
Route::prefix('v2')->namespace('App\Http\Controllers')->group(base_path('routes/api/v2/api.php'));

Route::get('/test', function () {
    return response()->json(['ok' => true]);
});
