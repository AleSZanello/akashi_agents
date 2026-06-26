// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'weather_query.dart';

// **************************************************************************
// SchemaGenerator
// **************************************************************************

Schema<WeatherQuery> get $weatherQuerySchema => Schema.object<WeatherQuery>(
  {
    'city': Schema.string(),
    'units': Schema.string(
      enumValues: ['metric', 'imperial'],
      description: 'metric or imperial',
    ),
    'note': Schema.string(),
  },
  required: ['city', 'units'],
  fromJson: _$WeatherQueryFromJson,
);

WeatherQuery _$WeatherQueryFromJson(Map<String, Object?> json) => WeatherQuery(
  city: json['city']! as String,
  units: json['units']! as String,
  note: json['note'] as String?,
);
