import { Body, Controller, Get, Param, Patch, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { AdminScope } from '../auth/auth.decorators';
import { CurrentAdmin } from '../auth/current-admin.decorator';
import { AdminIdentity } from '../domain';
import {
  CreateApplicationBodyDto,
  GetApplicationParamsDto,
  ListApplicationsQueryDto,
  UpdateApplicationBodyDto,
  UpdateApplicationParamsDto,
} from '../generated/request-dtos';
import { ApplicationsService } from './applications.service';

@ApiTags('applications')
@ApiBearerAuth()
@AdminScope('apps:manage')
@Controller('admin/v1/apps')
export class ApplicationsController {
  constructor(private readonly applications: ApplicationsService) {}

  @Post()
  create(@Body() body: CreateApplicationBodyDto, @CurrentAdmin() admin: AdminIdentity) {
    return this.applications.create(body, admin.subject);
  }

  @Get()
  list(@Query() query: ListApplicationsQueryDto) {
    return this.applications.list(query.cursor, query.limit);
  }

  @Get(':appId')
  get(@Param() params: GetApplicationParamsDto) {
    return this.applications.get(params.appId);
  }

  @Patch(':appId')
  update(
    @Param() params: UpdateApplicationParamsDto,
    @Body() body: UpdateApplicationBodyDto,
    @CurrentAdmin() admin: AdminIdentity,
  ) {
    return this.applications.update(params.appId, body, admin.subject);
  }
}
