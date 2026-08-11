import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  Param,
  Patch,
  Post,
  Put,
  Query,
} from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentIdentity } from '../auth/current-identity.decorator';
import { ExternalIdentity } from '../domain';
import {
  CancelRoomAccessRequestParamsDto,
  CreateRoomBodyDto,
  DecideJoinRequestBodyDto,
  DecideJoinRequestParamsDto,
  DeleteRoomParamsDto,
  GetRoomParamsDto,
  LeaveRoomParamsDto,
  ListMyJoinRequestsQueryDto,
  ListRoomJoinRequestsParamsDto,
  ListRoomJoinRequestsQueryDto,
  ListRoomsQueryDto,
  RemoveRoomMemberParamsDto,
  RequestRoomAccessParamsDto,
  TransferRoomOwnershipBodyDto,
  TransferRoomOwnershipParamsDto,
} from '../generated/request-dtos';
import { RealtimePublisher } from '../realtime/realtime.publisher';
import { RoomsService } from './rooms.service';

@ApiTags('rooms')
@ApiBearerAuth()
@Controller('v1')
export class RoomsController {
  constructor(private readonly rooms: RoomsService, private readonly realtime: RealtimePublisher) {}

  @Post('rooms')
  async create(@Body() body: CreateRoomBodyDto, @CurrentIdentity() identity: ExternalIdentity) {
    const room = await this.rooms.create(body.title, identity);
    this.realtime.publishRoom(identity.appId, room.id, 'room.state', room, room.version);
    return room;
  }

  @Get('rooms')
  list(
    @CurrentIdentity() identity: ExternalIdentity,
    @Query() query: ListRoomsQueryDto,
  ) {
    return this.rooms.list(identity, query.cursor, query.limit);
  }

  @Get('rooms/:roomId')
  get(@Param() params: GetRoomParamsDto, @CurrentIdentity() identity: ExternalIdentity) {
    return this.rooms.get(params.roomId, identity);
  }

  @Post('rooms/:roomId/join-requests')
  async requestJoin(@Param() params: RequestRoomAccessParamsDto, @CurrentIdentity() identity: ExternalIdentity) {
    const result = await this.rooms.requestJoin(params.roomId, identity);
    if (result.created) {
      const ownerUserId = await this.rooms.ownerUserId(params.roomId, identity.appId);
      this.realtime.publishUser(
        identity.appId,
        ownerUserId,
        'join-request.created',
        result.request,
        params.roomId,
        null,
      );
    }
    return result.request;
  }

  @Get('join-requests')
  myRequests(
    @CurrentIdentity() identity: ExternalIdentity,
    @Query() query: ListMyJoinRequestsQueryDto,
  ) {
    return this.rooms.listMyJoinRequests(identity, query.cursor, query.limit);
  }

  @Get('rooms/:roomId/join-requests')
  roomRequests(
    @Param() params: ListRoomJoinRequestsParamsDto,
    @CurrentIdentity() identity: ExternalIdentity,
    @Query() query: ListRoomJoinRequestsQueryDto,
  ) {
    return this.rooms.listRoomJoinRequests(params.roomId, identity, query.cursor, query.limit);
  }

  @Delete('rooms/:roomId/join-requests')
  @HttpCode(204)
  async cancelRequest(@Param() params: CancelRoomAccessRequestParamsDto, @CurrentIdentity() identity: ExternalIdentity) {
    await this.rooms.cancelJoinRequest(params.roomId, identity);
  }

  @Patch('rooms/:roomId/join-requests/:requestId')
  async decideRequest(
    @Param() params: DecideJoinRequestParamsDto,
    @Body() body: DecideJoinRequestBodyDto,
    @CurrentIdentity() identity: ExternalIdentity,
  ) {
    const result = await this.rooms.decideJoinRequest(params.roomId, params.requestId, body.decision, identity);
    this.realtime.publishUser(
      identity.appId,
      result.request.userId,
      'join-request.updated',
      result.request,
      params.roomId,
      null,
    );
    if (result.roomVersion) {
      const room = await this.rooms.snapshot(identity.appId, params.roomId);
      if (room) this.realtime.publishRoom(identity.appId, params.roomId, 'room.state', room, room.version);
    }
    return result.request;
  }

  @Delete('rooms/:roomId/members/me')
  @HttpCode(204)
  async leave(@Param() params: LeaveRoomParamsDto, @CurrentIdentity() identity: ExternalIdentity) {
    const room = await this.rooms.leave(params.roomId, identity);
    await this.realtime.evictUser(identity.appId, params.roomId, identity.userId);
    this.realtime.publishUser(identity.appId, identity.userId, 'membership.updated', { roomId: params.roomId, active: false }, params.roomId, room.version);
    this.realtime.publishRoom(identity.appId, params.roomId, 'room.state', room, room.version);
  }

  @Delete('rooms/:roomId/members/:userId')
  @HttpCode(204)
  async removeMember(
    @Param() params: RemoveRoomMemberParamsDto,
    @CurrentIdentity() identity: ExternalIdentity,
  ) {
    const room = await this.rooms.removeMember(params.roomId, params.userId, identity);
    this.realtime.publishUser(identity.appId, params.userId, 'membership.updated', { roomId: params.roomId, active: false }, params.roomId, room.version);
    await this.realtime.evictUser(identity.appId, params.roomId, params.userId);
    this.realtime.publishRoom(identity.appId, params.roomId, 'room.state', room, room.version);
  }

  @Put('rooms/:roomId/owner')
  async transferOwner(
    @Param() params: TransferRoomOwnershipParamsDto,
    @Body() body: TransferRoomOwnershipBodyDto,
    @CurrentIdentity() identity: ExternalIdentity,
  ) {
    const room = await this.rooms.transferOwnership(params.roomId, body.userId, identity);
    this.realtime.publishRoom(identity.appId, params.roomId, 'room.state', room, room.version);
    return room;
  }

  @Delete('rooms/:roomId')
  @HttpCode(204)
  async delete(@Param() params: DeleteRoomParamsDto, @CurrentIdentity() identity: ExternalIdentity) {
    const { userIds, roomVersion } = await this.rooms.delete(params.roomId, identity);
    for (const userId of userIds) {
      this.realtime.publishUser(identity.appId, userId, 'membership.updated', { roomId: params.roomId, active: false }, params.roomId, roomVersion);
      await this.realtime.evictUser(identity.appId, params.roomId, userId);
    }
  }
}
