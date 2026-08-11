// GENERATED FILE. Run npm run generate:contracts; do not edit.
import { Type } from 'class-transformer';
import { IsBoolean, IsDefined, IsIn, IsInt, IsOptional, IsString, IsUUID, IsUrl, Matches, Max, MaxLength, Min, MinLength, Validate, ValidateIf, ValidationArguments, ValidatorConstraint, ValidatorConstraintInterface } from 'class-validator';

@ValidatorConstraint({ name: 'minimumDefinedProperties', async: false })
class MinimumDefinedPropertiesConstraint implements ValidatorConstraintInterface {
  validate(_value: unknown, arguments_: ValidationArguments) {
    const [minimum, names] = arguments_.constraints as [number, readonly string[]];
    const object = arguments_.object as Record<string, unknown>;
    return !Object.prototype.hasOwnProperty.call(object, arguments_.property)
      && names.filter((name) => object[name] !== undefined).length >= minimum;
  }

  defaultMessage(arguments_: ValidationArguments) {
    return `Request body must define at least ${arguments_.constraints[0]} property`;
  }
}

export class ListApplicationsQueryDto {
  @ValidateIf((_object, value) => value !== undefined)
  @IsString()
  @MinLength(1)
  @MaxLength(256)
  cursor?: string;

  @ValidateIf((_object, value) => value !== undefined)
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number = 50;
}

export class CreateApplicationBodyDto {
  @IsDefined()
  @IsString()
  @Matches(new RegExp("^[A-Za-z0-9._-]{1,64}$"))
  appId!: string;

  @IsDefined()
  @IsString()
  @MinLength(1)
  issuer!: string;

  @IsDefined()
  @IsString()
  @MinLength(1)
  audience!: string;

  @IsDefined()
  @IsString()
  @IsUrl({ require_protocol: true, require_tld: false })
  @Matches(new RegExp("^https?://"))
  jwksUri!: string;

  @ValidateIf((_object, value) => value !== undefined)
  @IsBoolean()
  enabled?: boolean = true;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(36500)
  chatRetentionDays?: number | null;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(36500)
  sessionRetentionDays?: number | null;
}

export class GetApplicationParamsDto {
  @IsDefined()
  @IsString()
  @Matches(new RegExp("^[A-Za-z0-9._-]{1,64}$"))
  appId!: string;
}

export class UpdateApplicationParamsDto {
  @IsDefined()
  @IsString()
  @Matches(new RegExp("^[A-Za-z0-9._-]{1,64}$"))
  appId!: string;
}

export class UpdateApplicationBodyDto {
  @ValidateIf((_object, value) => value !== undefined)
  @IsString()
  @MinLength(1)
  issuer?: string;

  @ValidateIf((_object, value) => value !== undefined)
  @IsString()
  @MinLength(1)
  audience?: string;

  @ValidateIf((_object, value) => value !== undefined)
  @IsString()
  @IsUrl({ require_protocol: true, require_tld: false })
  @Matches(new RegExp("^https?://"))
  jwksUri?: string;

  @ValidateIf((_object, value) => value !== undefined)
  @IsBoolean()
  enabled?: boolean;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(36500)
  chatRetentionDays?: number | null;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(36500)
  sessionRetentionDays?: number | null;
}

Validate(MinimumDefinedPropertiesConstraint, [1, ["issuer","audience","jwksUri","enabled","chatRetentionDays","sessionRetentionDays"]])(UpdateApplicationBodyDto.prototype, '__minimumDefinedProperties');

export class ListRoomsQueryDto {
  @ValidateIf((_object, value) => value !== undefined)
  @IsString()
  @IsUUID()
  cursor?: string;

  @ValidateIf((_object, value) => value !== undefined)
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number = 50;
}

export class CreateRoomBodyDto {
  @IsDefined()
  @IsString()
  @MinLength(1)
  @MaxLength(100)
  @Matches(new RegExp("\\S"))
  title!: string;
}

export class GetRoomParamsDto {
  @IsDefined()
  @IsString()
  @IsUUID()
  roomId!: string;
}

export class DeleteRoomParamsDto {
  @IsDefined()
  @IsString()
  @IsUUID()
  roomId!: string;
}

export class ListRoomJoinRequestsParamsDto {
  @IsDefined()
  @IsString()
  @IsUUID()
  roomId!: string;
}

export class ListRoomJoinRequestsQueryDto {
  @ValidateIf((_object, value) => value !== undefined)
  @IsString()
  @IsUUID()
  cursor?: string;

  @ValidateIf((_object, value) => value !== undefined)
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number = 50;
}

export class RequestRoomAccessParamsDto {
  @IsDefined()
  @IsString()
  @IsUUID()
  roomId!: string;
}

export class CancelRoomAccessRequestParamsDto {
  @IsDefined()
  @IsString()
  @IsUUID()
  roomId!: string;
}

export class DecideJoinRequestParamsDto {
  @IsDefined()
  @IsString()
  @IsUUID()
  roomId!: string;

  @IsDefined()
  @IsString()
  @IsUUID()
  requestId!: string;
}

export class DecideJoinRequestBodyDto {
  @IsDefined()
  @IsString()
  @IsIn(["approved","rejected"])
  decision!: "approved" | "rejected";
}

export class ListMyJoinRequestsQueryDto {
  @ValidateIf((_object, value) => value !== undefined)
  @IsString()
  @IsUUID()
  cursor?: string;

  @ValidateIf((_object, value) => value !== undefined)
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number = 50;
}

export class RemoveRoomMemberParamsDto {
  @IsDefined()
  @IsString()
  @IsUUID()
  roomId!: string;

  @IsDefined()
  @IsString()
  @MinLength(1)
  @MaxLength(256)
  userId!: string;
}

export class LeaveRoomParamsDto {
  @IsDefined()
  @IsString()
  @IsUUID()
  roomId!: string;
}

export class TransferRoomOwnershipParamsDto {
  @IsDefined()
  @IsString()
  @IsUUID()
  roomId!: string;
}

export class TransferRoomOwnershipBodyDto {
  @IsDefined()
  @IsString()
  @MinLength(1)
  @MaxLength(256)
  userId!: string;
}

export class ListMessagesParamsDto {
  @IsDefined()
  @IsString()
  @IsUUID()
  roomId!: string;
}

export class ListMessagesQueryDto {
  @ValidateIf((_object, value) => value !== undefined)
  @IsString()
  @IsUUID()
  cursor?: string;

  @ValidateIf((_object, value) => value !== undefined)
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number = 50;
}

export class SendMessageParamsDto {
  @IsDefined()
  @IsString()
  @IsUUID()
  roomId!: string;
}

export class SendMessageBodyDto {
  @IsDefined()
  @IsString()
  @MinLength(1)
  @MaxLength(2000)
  @Matches(new RegExp("\\S"))
  text!: string;
}

export class StartSessionParamsDto {
  @IsDefined()
  @IsString()
  @IsUUID()
  roomId!: string;
}

export class ListActiveSessionsParamsDto {
  @IsDefined()
  @IsString()
  @IsUUID()
  roomId!: string;
}

export class ListActiveSessionsQueryDto {
  @ValidateIf((_object, value) => value !== undefined)
  @IsString()
  @IsUUID()
  cursor?: string;

  @ValidateIf((_object, value) => value !== undefined)
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number = 50;
}

export class UpdateSessionParamsDto {
  @IsDefined()
  @IsString()
  @IsUUID()
  sessionId!: string;
}

export class UpdateSessionBodyDto {
  @IsDefined()
  @IsString()
  @IsIn(["running","paused","finished"])
  status!: "running" | "paused" | "finished";
}
