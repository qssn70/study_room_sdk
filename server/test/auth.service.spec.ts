import jwt from 'jsonwebtoken';
import { AuthService } from '../src/auth/auth.service';

describe('AuthService', () => {
  it('verifies external JWT bearer tokens with required claims', async () => {
    const service = new AuthService('secret');
    const token = jwt.sign(
      {
        sub: 'user-1',
        appId: 'app-1',
        displayName: 'Lin',
        avatarUrl: 'https://example.com/a.png',
      },
      'secret',
      { expiresIn: '5m' },
    );

    await expect(service.verifyBearer(`Bearer ${token}`)).resolves.toMatchObject({
      userId: 'user-1',
      appId: 'app-1',
      displayName: 'Lin',
    });
  });

  it('rejects tokens missing required study room claims', async () => {
    const service = new AuthService('secret');
    const token = jwt.sign({ sub: 'user-1' }, 'secret', { expiresIn: '5m' });

    await expect(service.verifyBearer(`Bearer ${token}`)).rejects.toThrow(
      'JWT is missing required claims',
    );
  });
});

