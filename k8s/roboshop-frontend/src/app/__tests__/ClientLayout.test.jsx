import { render, screen, waitFor } from '@testing-library/react';
import ClientLayout from '../ClientLayout';

describe('ClientLayout', () => {
    beforeEach(() => {
        localStorage.clear();
        global.fetch = jest.fn(() =>
            Promise.resolve({ json: () => Promise.resolve({ items: [{}, {}] }) })
        );
    });

    afterEach(() => {
        jest.resetAllMocks();
    });

    it('renders brand, children and footer', () => {
        render(
            <ClientLayout>
                <p>child content</p>
            </ClientLayout>
        );
        expect(
            screen.getByRole('link', { name: /roboshop/i })
        ).toHaveAttribute('href', '/');
        expect(screen.getByText('child content')).toBeInTheDocument();
        expect(screen.getByText(/2024 roboshop/i)).toBeInTheDocument();
    });

    it('shows Login and Register links when no user is logged in', () => {
        render(<ClientLayout>x</ClientLayout>);
        expect(screen.getByRole('link', { name: /login/i })).toHaveAttribute(
            'href',
            '/login'
        );
        expect(screen.getByRole('link', { name: /register/i })).toHaveAttribute(
            'href',
            '/register'
        );
        expect(
            screen.queryByRole('button', { name: /logout/i })
        ).not.toBeInTheDocument();
    });

    it('shows the user greeting, logout button and cart count when logged in', async () => {
        localStorage.setItem('token', 'tok');
        localStorage.setItem(
            'user',
            JSON.stringify({ id: 3, firstName: 'Ada', username: 'ada' })
        );

        render(<ClientLayout>x</ClientLayout>);

        expect(await screen.findByText(/hi, ada/i)).toBeInTheDocument();
        expect(screen.getByRole('button', { name: /logout/i })).toBeInTheDocument();
        expect(
            screen.queryByRole('link', { name: /^login$/i })
        ).not.toBeInTheDocument();

        // fetchCartCount hits the cart endpoint with the user id
        await waitFor(() =>
            expect(global.fetch).toHaveBeenCalledWith('/api/cart/3')
        );
        expect(await screen.findByText('2')).toBeInTheDocument();
    });
});
