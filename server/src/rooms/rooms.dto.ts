import { Transform, Type } from 'class-transformer';
import { IsIn, IsInt, IsNotEmpty, IsOptional, IsString, IsUUID, Max, MaxLength, Min, MinLength } from 'class-validator';

export class CreateRoomDto {
  @Transform(({ value }) => typeof value === 'string' ? value.trim() : value)
  @IsString() @MinLength(1) @MaxLength(100)
  title!: string;
}

export class DecideJoinRequestDto {
  @IsIn(['approved', 'rejected'])
  decision!: 'approved' | 'rejected';
}

export class TransferOwnershipDto {
  @Transform(({ value }) => typeof value === 'string' ? value.trim() : value)
  @IsString() @IsNotEmpty()
  userId!: string;
}

export class RoomIdDto {
  @IsUUID()
  roomId!: string;
}

export class RoomPageQueryDto {
  @IsOptional() @IsUUID('4')
  cursor?: string;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(100)
  limit = 50;
}
