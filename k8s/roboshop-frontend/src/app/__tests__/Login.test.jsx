import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import Login from '../login/page';

describe('Login page', () => {
    let originalLocation;

    beforeEach(() => {
        localStorage.clear();
        // window.location.href assignment triggers a jsdom navigation error;
        // replace it with a writable stub so the component can "navigate".
        originalLocation = window.location;
        delete window.location;
        window.location = { href: '' };
    });

    afterEach(() => {
        window.location = originalLocation;
        jest.resetAllMocks();
    });

    it('renders the login form', () => {
        render(<Login />);
        expect(
            screen.getByRole('heading', { name: /^login$/i })
        ).toBeInTheDocument();
        expect(screen.getByPlaceholderText(/enter username/i)).toBeInTheDocument();
        expect(screen.getByPlaceholderText(/enter password/i)).toBeInTheDocument();
        expect(screen.getByRole('link', { name: /register here/i })).toHaveAttribute(
            'href',
            '/register'
        );
    });

    it('submits credentials to the login endpoint with the correct request shape', async () => {
        global.fetch = jest.fn(() =>
            Promise.resolve({
                json: () =>
                    Promise.resolve({ token: 'tok-123', user: { id: 7, username: 'admin' } }),
            })
        );
        const user = userEvent.setup();
        render(<Login />);

        await user.type(screen.getByPlaceholderText(/enter username/i), 'admin');
        await user.type(screen.getByPlaceholderText(/enter password/i), 'secret');
        await user.click(screen.getByRole('button', { name: /^login$/i }));

        await waitFor(() => expect(global.fetch).toHaveBeenCalledTimes(1));
        expect(global.fetch).toHaveBeenCalledWith('/api/user/login', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ username: 'admin', password: 'secret' }),
        });

        // On success it stores token + user and navigates home.
        await waitFor(() => expect(localStorage.getItem('token')).toBe('tok-123'));
        expect(JSON.parse(localStorage.getItem('user'))).toEqual({
            id: 7,
            username: 'admin',
        });
    });

    it('shows an error message when the API returns no token', async () => {
        global.fetch = jest.fn(() =>
            Promise.resolve({
                json: () => Promise.resolve({ error: 'Invalid credentials' }),
            })
        );
        const user = userEvent.setup();
        render(<Login />);

        await user.type(screen.getByPlaceholderText(/enter username/i), 'bad');
        await user.type(screen.getByPlaceholderText(/enter password/i), 'wrong');
        await user.click(screen.getByRole('button', { name: /^login$/i }));

        expect(await screen.findByText('Invalid credentials')).toBeInTheDocument();
        expect(localStorage.getItem('token')).toBeNull();
    });

    it('shows a generic error when fetch rejects', async () => {
        global.fetch = jest.fn(() => Promise.reject(new Error('network down')));
        const user = userEvent.setup();
        render(<Login />);

        await user.type(screen.getByPlaceholderText(/enter username/i), 'x');
        await user.type(screen.getByPlaceholderText(/enter password/i), 'y');
        await user.click(screen.getByRole('button', { name: /^login$/i }));

        expect(await screen.findByText('Login failed')).toBeInTheDocument();
    });
});
