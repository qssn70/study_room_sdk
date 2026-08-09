import { Transform, Type } from 'class-transformer';
import { IsInt, IsOptional, IsString, IsUUID, Max, MaxLength, Min, MinLength } from 'class-validator';

export class SendMessageDto {
  @Transform(({ value }) => typeof value === 'string' ? value.trim() : value)
  @IsString() @MinLength(1) @MaxLength(2000)
  text!: string;
}

export class MessagePageQueryDto {
  @IsOptional() @IsUUID('4')
  cursor?: string;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(100)
  limit = 50;
}
