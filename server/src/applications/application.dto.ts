import { Type } from 'class-transformer';
import { IsBoolean, IsInt, IsNotEmpty, IsOptional, IsString, IsUrl, Matches, Max, Min } from 'class-validator';

export class CreateApplicationDto {
  @Matches(/^[A-Za-z0-9._-]{1,64}$/)
  appId!: string;
  @IsString() @IsNotEmpty()
  issuer!: string;
  @IsString() @IsNotEmpty()
  audience!: string;
  @IsUrl({ require_protocol: true, require_tld: false })
  jwksUri!: string;
  @IsOptional() @IsBoolean()
  enabled?: boolean;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(36500)
  chatRetentionDays?: number | null;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(36500)
  sessionRetentionDays?: number | null;
}

export class UpdateApplicationDto {
  @IsOptional() @IsString() @IsNotEmpty()
  issuer?: string;
  @IsOptional() @IsString() @IsNotEmpty()
  audience?: string;
  @IsOptional() @IsUrl({ require_protocol: true, require_tld: false })
  jwksUri?: string;
  @IsOptional() @IsBoolean()
  enabled?: boolean;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(36500)
  chatRetentionDays?: number | null;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(36500)
  sessionRetentionDays?: number | null;
}
